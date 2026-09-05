import Foundation
import FirebaseDatabase

private enum FinalizationError: Error {
    case staleQuestion
    case answeringNotClosed
}

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
            ensureCPUAnswers(state: state, game: game)
            // 全員が回答権を使い切ったら、制限時間を待たずに採点して発表へ進む
            if hasEveryoneAnswered(state: state, game: game) {
                finishQuestion(index: game.questionIndex)
            } else {
                applyLiveScoring(state: state, game: game)
            }
        case .reveal:
            cancelQuestionTimer()
            cancelCPUAnswerTasks()
            if game.reveal == nil {
                // phaseだけ確定して結果書き込みが未完了なら、再接続時もここから再開する。
                finishQuestion(index: game.questionIndex)
            } else {
                scheduleAdvance(state: state, game: game)
            }
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
        hostWriteTask?.cancel()
        hostWriteTask = nil
        questionFinalizationTask?.cancel()
        questionFinalizationTask = nil
        cancelCPUAnswerTasks()
    }

    /// 参加者全員が1回ずつ回答を終えたか(正誤は問わない)
    private func hasEveryoneAnswered(state: RoomState, game: RoomState.Game) -> Bool {
        guard !state.players.isEmpty else { return false }
        let answeredIDs = Set(acceptedAnswers(state: state, game: game).map(\.uid))
        return state.players.allSatisfy { player in
            let isCPU = CPUProfile.roster.contains { $0.id == player.id }
            return (isCPU && !participatingCPUIds.contains(player.id))
                || answeredIDs.contains(player.id)
        }
    }

    // MARK: - NPC回答

    /// オンラインでも既存CPUAnswerStrategyで参加・回答内容・回答時刻を決める。
    /// 実際のRTDB書き込みだけをhostが担当し、guest端末ではNPCロジックを動かさない。
    private func ensureCPUAnswers(state: RoomState, game: RoomState.Game) {
        guard state.questions.indices.contains(game.questionIndex) else { return }
        let questionKey = (game.questionIndex, game.effectiveStartedAtMS)
        if scheduledCPUQuestion?.index != questionKey.0
            || scheduledCPUQuestion?.effectiveStartedAtMS != questionKey.1 {
            cancelCPUAnswerTasks()
            scheduledCPUQuestion = questionKey
            participatingCPUIds = []

            let question = state.questions[game.questionIndex]
            let profiles = state.players.compactMap { player in
                CPUProfile.roster.first { $0.id == player.id }
            }
            for profile in profiles where cpuAnswerStrategy.participates(profile) {
                participatingCPUIds.insert(profile.id)
                let plan = cpuAnswerStrategy.progressivePlan(
                    for: profile,
                    question: question,
                    timeLimit: state.settings.timeLimit
                )
                let answerAtMS = game.effectiveStartedAtMS + plan.delay * 1_000
                let remaining = max(0, (answerAtMS - battleTimeMS(at: .now)) / 1_000)
                cpuAnswerTasks[profile.id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(remaining))
                    guard !Task.isCancelled, let self else { return }
                    await self.submitCPUAnswer(
                        profileID: profile.id,
                        choice: plan.choice,
                        visibleCount: plan.visibleCount,
                        questionIndex: game.questionIndex,
                        effectiveStartedAtMS: game.effectiveStartedAtMS
                    )
                }
            }
        }
    }

    private func submitCPUAnswer(
        profileID: String,
        choice: String,
        visibleCount: Int,
        questionIndex: Int,
        effectiveStartedAtMS: Double
    ) async {
        guard isHost,
              let state,
              state.status == .playing,
              let game = state.game,
              game.phase == .question,
              game.questionIndex == questionIndex,
              game.effectiveStartedAtMS == effectiveStartedAtMS,
              state.players.contains(where: { $0.id == profileID }),
              !game.failedIDs.contains(profileID),
              !game.answers.contains(where: { $0.uid == profileID }) else { return }

        do {
            try await roomRef.child("game/answers/\(profileID)").setValue([
                "questionIndex": questionIndex,
                "choice": choice,
                "ts": ServerValue.timestamp(),
                "visibleCount": visibleCount
            ])
        } catch {
            lastError = "NPCの回答を送信できませんでした"
            print("NPC回答の送信に失敗: \(error)")
        }
    }

    private func cancelCPUAnswerTasks() {
        cpuAnswerTasks.values.forEach { $0.cancel() }
        cpuAnswerTasks = [:]
        scheduledCPUQuestion = nil
        participatingCPUIds = []
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
        guard scoredQuestionIndex != game.questionIndex else { return }
        guard let updates = scoringUpdates(state: state, game: game), !updates.isEmpty else { return }
        write(updates, failureMessage: "回答の反映に失敗しました")
    }

    /// 採点結果を、現在の状態と違う項目だけの差分にして返す。
    /// 差分が無いときに書き込まないことで、自分の書き込みで再び観測が走る往復を止める
    private func scoringUpdates(state: RoomState, game: RoomState.Game) -> [String: Any]? {
        guard state.questions.indices.contains(game.questionIndex),
              let base = questionBaseScores, base.index == game.questionIndex else { return nil }
        let question = state.questions[game.questionIndex]
        let validAnswers = acceptedAnswers(state: state, game: game)
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
            updates["game/failed/\(uid)"] = ["questionIndex": game.questionIndex]
        }
        return updates
    }

    // MARK: - 制限時間終了時の一括採点

    private func ensureQuestionTimer(game: RoomState.Game, timeLimit: TimeInterval) {
        // 同じ問題・同じ開始時刻ならタイマー設定済み
        if let timed = timedQuestion,
           timed.index == game.questionIndex,
           timed.effectiveStartedAtMS == game.effectiveStartedAtMS,
           timed.clockOffsetMS == battleClockOffsetMS {
            return
        }
        cancelQuestionTimer()
        timedQuestion = (game.questionIndex, game.effectiveStartedAtMS, battleClockOffsetMS)

        let index = game.questionIndex
        let elapsed = (battleTimeMS(at: .now) - game.effectiveStartedAtMS) / 1_000
        let remaining = max(0, timeLimit - elapsed)
        questionTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishQuestion(index: index)
        }
    }

    /// 最終的な採点を確定して発表へ進む。制限時間切れと「全員が回答済み」の両方から呼ばれる。
    /// 先にgameのtransactionで受付を閉じ、その確定スナップショットだけを採点する。
    private func finishQuestion(index: Int) {
        guard scoredQuestionIndex != index else { return }
        guard let state, state.status == .playing,
              let game = state.game,
              game.phase == .question || (game.phase == .reveal && game.reveal == nil),
              game.questionIndex == index,
              state.questions.indices.contains(index),
              let base = questionBaseScores, base.index == index else { return }
        scoredQuestionIndex = index

        let previousWrite = hostWriteTask
        questionFinalizationTask?.cancel()
        questionFinalizationTask = Task { [weak self] in
            await previousWrite?.value
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.finalizeQuestion(
                    index: index,
                    state: state,
                    baseScores: base.scores
                )
                self.questionFinalizationTask = nil
            } catch {
                self.lastError = "問題の進行に失敗しました"
                print("問題の最終採点に失敗: \(error)")
                self.scoredQuestionIndex = nil
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self.questionFinalizationTask = nil
                self.finishQuestion(index: index)
            }
        }
    }

    /// `game`全体のtransactionはanswers配下の同時書き込みと競合して再試行される。
    /// そのためtransactionがphaseをrevealへ変えた時点のanswersが、受付終了時の唯一の集合になる。
    private func finalizeQuestion(
        index: Int,
        state: RoomState,
        baseScores: [String: Int]
    ) async throws {
        let gameRef = roomRef.child("game")
        let (_, snapshot) = try await gameRef.runTransactionBlock { mutableData in
            guard var value = mutableData.value as? [String: Any],
                  (value["questionIndex"] as? NSNumber)?.intValue == index,
                  let phase = value["phase"] as? String else {
                return TransactionResult.abort()
            }

            if phase == RoomState.GamePhase.question.rawValue {
                value["phase"] = RoomState.GamePhase.reveal.rawValue
                value.removeValue(forKey: "reveal")
                mutableData.value = value
                return TransactionResult.success(withValue: mutableData)
            }

            // 前回の確定書き込みが失敗してphaseだけrevealなら、同じ回答集合から再開する。
            return TransactionResult.abort()
        }

        guard let gameValue = snapshot.value as? [String: Any],
              let closedGame = RoomState.game(databaseValue: gameValue),
              closedGame.questionIndex == index else {
            throw FinalizationError.staleQuestion
        }
        if closedGame.reveal != nil {
            return
        }
        guard closedGame.phase == .reveal,
              state.questions.indices.contains(index) else {
            throw FinalizationError.answeringNotClosed
        }

        let question = state.questions[index]
        let accepted = BattleAnswerAcceptance.acceptedAnswers(
            in: closedGame,
            timeLimit: state.settings.timeLimit,
            participantIDs: state.players.map(\.id)
        )
        let scoring = BattleScoring.result(
            answers: accepted,
            correctAnswer: question.answer,
            participantIDs: state.players.map(\.id)
        )

        var updates: [String: Any] = [:]
        for player in state.players {
            updates["players/\(player.id)/score"] = (baseScores[player.id] ?? player.score)
                + (scoring.pointChanges[player.id] ?? 0)
        }
        if accepted.isEmpty {
            updates["game/answers"] = NSNull()
        } else {
            let acceptedValues: [String: [String: Any]] = Dictionary(
                uniqueKeysWithValues: accepted.map { answer in
                    (answer.uid, [
                        "questionIndex": answer.questionIndex,
                        "choice": answer.choice,
                        "ts": answer.answeredAtMS,
                        "visibleCount": answer.visibleCount
                    ])
                }
            )
            updates["game/answers"] = acceptedValues
        }
        if scoring.wrongIDs.isEmpty {
            updates["game/failed"] = NSNull()
        } else {
            updates["game/failed"] = Dictionary(
                uniqueKeysWithValues: scoring.wrongIDs.map {
                    ($0, ["questionIndex": index])
                }
            )
        }
        updates["game/reveal"] = [
            "correctAnswer": question.answer,
            "correctIDs": scoring.correctIDs
        ]

        // 得点・誤答状態・確定順位を同じRTDB更新で公開し、UIへ矛盾状態を見せない。
        try await roomRef.updateChildValues(updates)
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
        let previousWrite = hostWriteTask
        hostWriteTask = Task { [weak self] in
            await previousWrite?.value
            guard !Task.isCancelled, let self else { return }
            do {
                try await roomRef.updateChildValues(updates)
            } catch {
                lastError = failureMessage
                print("\(failureMessage): \(error)")
            }
            completion?()
        }
    }
}
