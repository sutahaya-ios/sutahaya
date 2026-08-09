import Foundation

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
        var correctIDs: [String] = []
        var wrongIDs: Set<String> = []
        for answer in orderedAnswers where seenIDs.insert(answer.uid).inserted {
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
