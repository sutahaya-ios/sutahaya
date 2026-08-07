import Foundation
import FirebaseDatabase

/// ホスト端末が持つ進行の権威(採点・回答権移行・タイムアウト・問題送り)
/// 状態観測(apply)のたびに hostReact が呼ばれるため、各処理は多重実行されないよう
/// マーカー(timedQuestion / answerTimerKey / revealScheduledIndex)でガードする
extension OnlineBattleSession {

    func hostReact(to state: RoomState) {
        guard state.status == .playing, let game = state.game else {
            stopHostTasks()
            return
        }

        switch game.phase {
        case .question:
            revealScheduledIndex = nil
            guard !state.settings.style.revealsProgressively else {
                // 文字送り型は早押しボタンが無く、届いた回答を早い順に採点していく
                cancelAnswerTimer()
                ensureQuestionTimer(game: game, timeLimit: state.settings.timeLimit)
                judgeAnswers(state: state, game: game)
                return
            }
            if let winner = game.buzzWinner {
                cancelQuestionTimer()
                ensureAnswerTimer(index: game.questionIndex, winner: winner)
                if let answer = game.answer {
                    evaluate(answer: answer, state: state, game: game)
                }
            } else {
                cancelAnswerTimer()
                ensureQuestionTimer(game: game, timeLimit: state.settings.timeLimit)
            }
        case .reveal:
            cancelQuestionTimer()
            cancelAnswerTimer()
            scheduleAdvance(state: state, game: game)
        case .finished:
            stopHostTasks()
        }
    }

    func stopHostTasks() {
        cancelQuestionTimer()
        cancelAnswerTimer()
        revealTask?.cancel()
        revealTask = nil
        revealScheduledIndex = nil
    }

    // MARK: - 文字送り型の採点(選択肢を押した順に判定する)

    /// 届いた回答を**押した時刻の早い順**に1件ずつ採点する。
    /// 最初に正解した人がその問題の勝者。誤答した人はこの問題に再回答できない
    func judgeAnswers(state: RoomState, game: RoomState.Game) {
        guard !isEvaluatingAnswer, state.questions.indices.contains(game.questionIndex) else { return }

        if judgedQuestionIndex != game.questionIndex {
            judgedQuestionIndex = game.questionIndex
            judgedUIDs = []
        }

        let pending = game.answers.filter { !judgedUIDs.contains($0.uid) && !game.failedIDs.contains($0.uid) }
        guard let target = pending.first else { return }

        isEvaluatingAnswer = true
        judgedUIDs.insert(target.uid)

        let question = state.questions[game.questionIndex]
        if target.choice == question.answer {
            applyCorrectAnswer(uid: target.uid, question: question, state: state)
        } else {
            applyWrongChoice(uid: target.uid, question: question, state: state, game: game)
        }
    }

    /// 誤答:−1点でこの問題から締め出す。全員が答え終えていたら待たずに発表へ進む
    private func applyWrongChoice(uid: String, question: RoomState.QuestionPayload,
                                  state: RoomState, game: RoomState.Game) {
        let newScore = (player(for: uid)?.score ?? 0) + BattleRules.wrongPoint
        var updates: [String: Any] = [
            "players/\(uid)/score": newScore,
            "game/buzz/failed/\(uid)": true
        ]

        let allFinished = state.players.allSatisfy { $0.id == uid || game.failedIDs.contains($0.id) }
        if allFinished {
            updates["game/phase"] = RoomState.GamePhase.reveal.rawValue
            updates["game/reveal"] = [
                "correctAnswer": question.answer,
                "scorerID": "",
                "byTimeout": true
            ]
        }

        write(updates, failureMessage: "採点に失敗しました") { [weak self] in
            self?.isEvaluatingAnswer = false
        }
    }

    // MARK: - 採点と回答権移行(要件 §5.1.2)

    private func evaluate(answer: (uid: String, choice: String), state: RoomState, game: RoomState.Game) {
        guard !isEvaluatingAnswer,
              answer.uid == game.buzzWinner,
              state.questions.indices.contains(game.questionIndex) else { return }
        isEvaluatingAnswer = true

        let question = state.questions[game.questionIndex]
        if answer.choice == question.answer {
            applyCorrectAnswer(uid: answer.uid, question: question, state: state)
        } else {
            applyWrongAnswer(uid: answer.uid, state: state, game: game)
        }
    }

    func applyCorrectAnswer(uid: String, question: RoomState.QuestionPayload, state: RoomState) {
        let newScore = (player(for: uid)?.score ?? 0) + BattleRules.correctPoint
        let updates: [String: Any] = [
            "players/\(uid)/score": newScore,
            "game/answer": NSNull(),
            "game/phase": RoomState.GamePhase.reveal.rawValue,
            "game/reveal": [
                "correctAnswer": question.answer,
                "scorerID": uid,
                "byTimeout": false
            ]
        ]
        write(updates, failureMessage: "採点に失敗しました") { [weak self] in
            self?.isEvaluatingAnswer = false
        }
    }

    /// 誤答(回答時間切れ含む):−1点で誤答者をロックし、押下順キューの次のプレイヤーへ回答権を移す。
    /// 誰も残っていなければ出題タイマーを仕切り直して早押し受付に戻す
    func applyWrongAnswer(uid: String, state: RoomState, game: RoomState.Game) {
        let newScore = (player(for: uid)?.score ?? 0) + BattleRules.wrongPoint
        let excluded = game.failedIDs.union([uid])
        let nextWinner = game.buzzQueue
            .filter { !excluded.contains($0.key) }
            .min { $0.value < $1.value }?
            .key

        var updates: [String: Any] = [
            "players/\(uid)/score": newScore,
            "game/answer": NSNull(),
            "game/buzz/failed/\(uid)": true,
            "game/buzz/winner": nextWinner ?? NSNull()
        ]
        if nextWinner == nil {
            // 残りのプレイヤーのために制限時間を仕切り直す
            updates["game/startedAt"] = ServerValue.timestamp()
        }
        write(updates, failureMessage: "回答権の移行に失敗しました") { [weak self] in
            self?.isEvaluatingAnswer = false
        }
    }

    // MARK: - 出題タイムアウト(誰も押さずに時間切れ → 問題が流れる)

    private func ensureQuestionTimer(game: RoomState.Game, timeLimit: TimeInterval) {
        // 同じ問題・同じ開始時刻ならタイマー設定済み(誤答での仕切り直しはstartedAtが変わる)
        if let timed = timedQuestion,
           timed.index == game.questionIndex, timed.startedAtMS == game.startedAtMS {
            return
        }
        cancelQuestionTimer()
        timedQuestion = (game.questionIndex, game.startedAtMS)

        let index = game.questionIndex
        let elapsed = Date().timeIntervalSince1970 - game.startedAtMS / 1000
        let remaining = max(0, timeLimit - elapsed)
        questionTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timeoutQuestion(index: index)
        }
    }

    private func timeoutQuestion(index: Int) {
        guard let state, state.status == .playing,
              let game = state.game,
              game.phase == .question,
              game.questionIndex == index,
              game.buzzWinner == nil,
              state.questions.indices.contains(index) else { return }

        let updates: [String: Any] = [
            "game/phase": RoomState.GamePhase.reveal.rawValue,
            "game/reveal": [
                "correctAnswer": state.questions[index].answer,
                "scorerID": "",
                "byTimeout": true
            ]
        ]
        write(updates, failureMessage: "問題の進行に失敗しました")
    }

    // MARK: - 回答時間切れ(回答権を持ったまま無回答 → 誤答扱い)

    private func ensureAnswerTimer(index: Int, winner: String) {
        let key = "\(index)-\(winner)"
        guard answerTimerKey != key else { return }
        cancelAnswerTimer()
        answerTimerKey = key

        answerTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(BattleRules.answerTimeLimit * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timeoutAnswer(index: index, winner: winner)
        }
    }

    private func timeoutAnswer(index: Int, winner: String) {
        guard let state, state.status == .playing,
              let game = state.game,
              game.phase == .question,
              game.questionIndex == index,
              game.buzzWinner == winner else { return }
        applyWrongAnswer(uid: winner, state: state, game: game)
    }

    // MARK: - 正解発表後の問題送り

    private func scheduleAdvance(state: RoomState, game: RoomState.Game) {
        guard revealScheduledIndex != game.questionIndex else { return }
        revealScheduledIndex = game.questionIndex

        let index = game.questionIndex
        let isLast = index + 1 >= state.questions.count
        revealTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(BattleRules.revealDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.advance(from: index, isLast: isLast)
        }
    }

    private func advance(from index: Int, isLast: Bool) {
        guard let state, state.status == .playing,
              let game = state.game,
              game.phase == .reveal,
              game.questionIndex == index else { return }

        let updates: [String: Any]
        if isLast {
            updates = [
                "status": RoomState.Status.finished.rawValue,
                "game/phase": RoomState.GamePhase.finished.rawValue
            ]
        } else {
            updates = [
                "game/questionIndex": index + 1,
                "game/phase": RoomState.GamePhase.question.rawValue,
                "game/startedAt": ServerValue.timestamp(),
                "game/buzz": NSNull(),
                "game/answer": NSNull(),
                "game/answers": NSNull(),
                "game/reveal": NSNull()
            ]
        }
        write(updates, failureMessage: "問題の進行に失敗しました")
    }

    // MARK: - 共通

    private func cancelQuestionTimer() {
        questionTimerTask?.cancel()
        questionTimerTask = nil
        timedQuestion = nil
    }

    private func cancelAnswerTimer() {
        answerTimerTask?.cancel()
        answerTimerTask = nil
        answerTimerKey = nil
    }

    private func write(_ updates: [String: Any], failureMessage: String, completion: (() -> Void)? = nil) {
        Task { [weak self] in
            do {
                try await self?.roomRef.updateChildValues(updates)
            } catch {
                self?.lastError = failureMessage
                print("\(failureMessage): \(error)")
            }
            completion?()
        }
    }
}
