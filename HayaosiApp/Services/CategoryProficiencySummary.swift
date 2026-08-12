import Foundation

/// 指定カテゴリの習得率・難易度別正答率を、問題と解答履歴から集計する
struct CategoryProficiencySummary: Equatable {
    let totalWordCount: Int
    let masteredWordCount: Int
    let proficiencyRate: Double?

    private let accuracyByDifficultyValue: [Int: Double]

    func accuracy(for difficulty: WordDifficulty) -> Double? {
        accuracyByDifficultyValue[difficulty.rawValue]
    }

    static func calculate(
        records: [AnswerRecord],
        questions: [Question],
        category: WordCategory
    ) -> CategoryProficiencySummary {
        let categoryQuestionsByID = questions.reduce(into: [String: Question]()) { result, question in
            guard question.category == category else { return }
            result[question.id] = question
        }
        var masteredQuestionIDs = Set<String>()
        var countsByDifficulty = [Int: AccuracyCount]()

        for record in records {
            guard let question = categoryQuestionsByID[record.questionID] else {
                continue
            }

            if record.isCorrect {
                masteredQuestionIDs.insert(question.id)
            }
            countsByDifficulty[question.difficulty.rawValue, default: AccuracyCount()]
                .add(isCorrect: record.isCorrect)
        }

        let totalWordCount = categoryQuestionsByID.count
        let proficiencyRate = totalWordCount > 0
            ? Double(masteredQuestionIDs.count) / Double(totalWordCount)
            : nil
        let accuracyByDifficultyValue = countsByDifficulty.mapValues(\.accuracy)
        return CategoryProficiencySummary(
            totalWordCount: totalWordCount,
            masteredWordCount: masteredQuestionIDs.count,
            proficiencyRate: proficiencyRate,
            accuracyByDifficultyValue: accuracyByDifficultyValue
        )
    }
}

private struct AccuracyCount {
    private(set) var correct = 0
    private(set) var total = 0

    var accuracy: Double {
        Double(correct) / Double(total)
    }

    mutating func add(isCorrect: Bool) {
        total += 1
        if isCorrect {
            correct += 1
        }
    }
}
