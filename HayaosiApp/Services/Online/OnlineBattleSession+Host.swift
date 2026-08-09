import Foundation
import FirebaseDatabase

/// ホスト端末が持つ進行の権威(採点・タイムアウト・問題送り)
/// 状態観測(apply)のたびに hostReact が呼ばれるため、各処理は多重実行されないよう
/// マーカー(timedQuestion / revealScheduledIndex)でガードする
extension OnlineBattleSession {

    func hostReact(to state: RoomState) {
        guard state.status == .playing, let game = state.game else {
            stopHostTasks()
            return
        }

        switch game.phase {
        case .question:
            revealScheduledIndex = nil
            ensureQuestionTimer(game: game, timeLimit: state.settings.timeLimit)
            captureBaseScoresIfNeeded(state: state, game: game)
            // 全員が回答権を使い切ったら、制限時間を待たずに採点して発表へ進む
            if hasEveryoneAnswered(state: state, game: game) {
                finishQuestion(index: game.questionIndex)
            } else {
                applyLiveScoring(state: state, game: game)
            }
        case .reveal:
            cancelQuestionTimer()
            scheduleAdvance(state: state, game: game)
        case .finished:
            stopHostTasks()
        }
    }

    func stopHostTasks() {
        cancelQuestionTimer()
        revealTask?.cancel()
        revealTask = nil
        revealScheduledIndex = nil
        // 再戦で問題番号が0に戻っても採点できるようにする
        scoredQuestionIndex = nil
        questionBaseScores = nil
    }

    /// 参加者全員が1回ずつ回答を終えたか(正誤は問わない)
    private func hasEveryoneAnswered(state: RoomState, game: RoomState.Game) -> Bool {
        guard !state.players.isEmpty else { return false }
        let answeredIDs = Set(game.answers.map(\.uid))
        return state.players.allSatisfy { answeredIDs.contains($0.id) }
    }

    // MARK: - 回答状態の反映

    /// 問題を始めた時点の得点を控える。回答のたびにここから計算し直すことで、
    /// スナップショットが何度届いても得点が二重に動かない
    private func captureBaseScoresIfNeeded(state: RoomState, game: RoomState.Game) {
        guard questionBaseScores?.index != game.questionIndex else { return }
        questionBaseScores = (
            game.questionIndex,
            Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, $0.score) })
        )
    }

    /// いま届いている回答だけで採点し、確定した得点とお手つきを即座に反映する。
    /// 残りの回答を待つ間も、自分の結果が画面に出るようにするためのもの
    private func applyLiveScoring(state: RoomState, game: RoomState.Game) {
        guard let updates = scoringUpdates(state: state, game: game), !updates.isEmpty else { return }
        write(updates, failureMessage: "回答の反映に失敗しました")
    }

    /// 採点結果を、現在の状態と違う項目だけの差分にして返す。
    /// 差分が無いときに書き込まないことで、自分の書き込みで再び観測が走る往復を止める
    private func scoringUpdates(state: RoomState, game: RoomState.Game) -> [String: Any]? {
        guard state.questions.indices.contains(game.questionIndex),
              let base = questionBaseScores, base.index == game.questionIndex else { return nil }
        let question = state.questions[game.questionIndex]
        let deadlineMS = game.effectiveStartedAtMS + state.settings.timeLimit * 1_000
        let validAnswers = game.answers.filter { $0.answeredAtMS <= deadlineMS }
        let scoring = BattleScoring.result(
            answers: validAnswers,
            correctAnswer: question.answer,
            participantIDs: state.players.map(\.id)
        )

        var updates: [String: Any] = [:]
        for player in state.players {
            let baseScore = base.scores[player.id] ?? player.score
            let newScore = baseScore + (scoring.pointChanges[player.id] ?? 0)
            if newScore != player.score {
                updates["players/\(player.id)/score"] = newScore
            }
        }
        for uid in scoring.wrongIDs where !game.failedIDs.contains(uid) {
            updates["game/failed/\(uid)"] = true
        }
        return updates
    }

    // MARK: - 制限時間終了時の一括採点

    private func ensureQuestionTimer(game: RoomState.Game, timeLimit: TimeInterval) {
        // 同じ問題・同じ開始時刻ならタイマー設定済み
        if let timed = timedQuestion,
           timed.index == game.questionIndex,
           timed.effectiveStartedAtMS == game.effectiveStartedAtMS {
            return
        }
        cancelQuestionTimer()
        timedQuestion = (game.questionIndex, game.effectiveStartedAtMS)

        let index = game.questionIndex
        let elapsed = Date().timeIntervalSince1970 - game.effectiveStartedAtMS / 1_000
        let remaining = max(0, timeLimit - elapsed)
        questionTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishQuestion(index: index)
        }
    }

    /// 最終的な採点を確定して発表へ進む。制限時間切れと「全員が回答済み」の両方から呼ばれる。
    /// 得点は回答のたびに反映済みなので、ここでは残りの差分と発表内容だけを書き込む
    private func finishQuestion(index: Int) {
        guard scoredQuestionIndex != index else { return }
        guard let state, state.status == .playing,
              let game = state.game,
              game.phase == .question,
              game.questionIndex == index,
              state.questions.indices.contains(index) else { return }
        scoredQuestionIndex = index

        let question = state.questions[index]
        let deadlineMS = game.effectiveStartedAtMS + state.settings.timeLimit * 1_000
        let validAnswers = game.answers.filter { $0.answeredAtMS <= deadlineMS }
        let scoring = BattleScoring.result(
            answers: validAnswers,
            correctAnswer: question.answer,
            participantIDs: state.players.map(\.id)
        )

        var updates: [String: Any] = scoringUpdates(state: state, game: game) ?? [:]
        updates["game/phase"] = RoomState.GamePhase.reveal.rawValue
        updates["game/reveal"] = [
            "correctAnswer": question.answer,
            "correctIDs": scoring.correctIDs
        ]
        write(updates, failureMessage: "問題の進行に失敗しました")
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
                "game/startDelayMS": 0,
                "game/startedAt": ServerValue.timestamp(),
                "game/failed": NSNull(),
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
