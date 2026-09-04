import Foundation

/// オンライン・CPU共通の「この問題で受理された回答」の境界。
/// 順位・採点・全員回答済み判定・履歴は、必ずこの集合を入力にする。
enum BattleAnswerAcceptance {
    static func acceptedAnswers(
        in game: RoomState.Game,
        timeLimit: TimeInterval,
        participantIDs: [String]
    ) -> [RoomState.Answer] {
        let deadlineMS = game.effectiveStartedAtMS + timeLimit * 1_000
        let candidates = game.answers.filter {
            $0.questionIndex == game.questionIndex
                && $0.answeredAtMS >= game.effectiveStartedAtMS
                && $0.answeredAtMS <= deadlineMS
        }
        return orderedUniqueAnswers(candidates, participantIDs: participantIDs)
    }

    /// 出題中は時刻境界を通った回答、受付終了後はホストが確定結果へ含めた回答だけを返す。
    /// transaction後に生のanswersへ遅れて届いた回答を、順位や履歴へ混ぜないために使う。
    static func confirmedAnswers(
        in game: RoomState.Game,
        timeLimit: TimeInterval,
        participantIDs: [String]
    ) -> [RoomState.Answer] {
        let accepted = acceptedAnswers(
            in: game,
            timeLimit: timeLimit,
            participantIDs: participantIDs
        )
        guard game.phase != .question else { return accepted }
        guard let reveal = game.reveal else { return [] }
        let confirmedIDs = Set(reveal.correctIDs).union(game.failedIDs)
        return accepted.filter { confirmedIDs.contains($0.uid) }
    }

    /// Firebaseの保存完了ではなく、サーバーで確定した回答時刻を含めて受理されたかを返す。
    static func isAccepted(
        _ answer: RoomState.Answer,
        questionIndex: Int,
        effectiveStartedAtMS: Double,
        timeLimit: TimeInterval,
        participantIDs: [String]
    ) -> Bool {
        let game = RoomState.Game(
            questionIndex: questionIndex,
            phase: .question,
            startDelayMS: 0,
            startedAtMS: effectiveStartedAtMS,
            failedIDs: [],
            answers: [answer],
            reveal: nil
        )
        return !acceptedAnswers(
            in: game,
            timeLimit: timeLimit,
            participantIDs: participantIDs
        ).isEmpty
    }

    static func orderedUniqueAnswers(
        _ answers: [RoomState.Answer],
        participantIDs: [String]
    ) -> [RoomState.Answer] {
        let participantSet = Set(participantIDs)
        let tieBreakOrder = Dictionary(
            uniqueKeysWithValues: participantIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let orderedAnswers = answers
            .filter { participantSet.contains($0.uid) }
            .sorted { left, right in
                if left.answeredAtMS == right.answeredAtMS {
                    return (tieBreakOrder[left.uid] ?? Int.max) < (tieBreakOrder[right.uid] ?? Int.max)
                }
                return left.answeredAtMS < right.answeredAtMS
            }

        var seenIDs: Set<String> = []
        return orderedAnswers.filter { seenIDs.insert($0.uid).inserted }
    }

    /// 出題中の順位は、同じ回答集合から算出した得点が全員分反映された後だけ表示する。
    static func scoresMatch(
        answers: [RoomState.Answer],
        correctAnswer: String,
        participantIDs: [String],
        baseScores: [String: Int],
        currentScores: [String: Int]
    ) -> Bool {
        let scoring = BattleScoring.result(
            answers: answers,
            correctAnswer: correctAnswer,
            participantIDs: participantIDs
        )
        return participantIDs.allSatisfy { uid in
            let expected = (baseScores[uid] ?? currentScores[uid] ?? 0)
                + (scoring.pointChanges[uid] ?? 0)
            return currentScores[uid] == expected
        }
    }
}

/// 1問ぶんの回答を、正解者内の順位に応じた点差へ変換する純粋ロジック
enum BattleScoring {
    struct Result: Equatable {
        let correctIDs: [String]
        let wrongIDs: Set<String>
        let pointChanges: [String: Int]
    }

    static func result(
        answers: [RoomState.Answer],
        correctAnswer: String,
        participantIDs: [String]
    ) -> Result {
        let orderedAnswers = BattleAnswerAcceptance.orderedUniqueAnswers(
            answers,
            participantIDs: participantIDs
        )

        var correctIDs: [String] = []
        var wrongIDs: Set<String> = []
        for answer in orderedAnswers {
            if answer.choice == correctAnswer {
                correctIDs.append(answer.uid)
            } else {
                wrongIDs.insert(answer.uid)
            }
        }

        var pointChanges = Dictionary(
            uniqueKeysWithValues: wrongIDs.map { ($0, BattleRules.wrongPoint) }
        )
        for (index, uid) in correctIDs.enumerated() {
            pointChanges[uid] = BattleRules.correctPoint(for: index + 1)
        }

        return Result(correctIDs: correctIDs, wrongIDs: wrongIDs, pointChanges: pointChanges)
    }
}
