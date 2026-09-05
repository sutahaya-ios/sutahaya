import Foundation

/// 指定カテゴリ(必要なら難易度も絞って)の習得率・難易度別正答率を、問題と解答履歴から集計する
struct CategoryProficiencySummary: Equatable {
    let totalWordCount: Int
    let masteredWordCount: Int
    let proficiencyRate: Double?

    private let accuracyByDifficultyValue: [Int: Double]

    func accuracy(for difficulty: WordDifficulty) -> Double? {
        accuracyByDifficultyValue[difficulty.rawValue]
    }

    /// 学習記録と対戦ホームで同じ表記を使うため、文字列はここを唯一の出典にする
    var rateText: String {
        guard let proficiencyRate else { return "－" }
        return "\(Int(proficiencyRate * 100))%"
    }

    /// 「1語 / 400語」形式。対戦ホームのように分母を強調したい場所で使う
    var masteredOverTotalText: String {
        guard totalWordCount > 0 else { return "－" }
        return "\(masteredWordCount)語 / \(totalWordCount)語"
    }

    var detailText: String {
        guard totalWordCount > 0 else { return "－" }
        return "\(totalWordCount)語中\(masteredWordCount)語"
    }

    /// 0...1 に収めた進捗。バー・円環のどちらでもそのまま使える
    var progress: Double {
        min(max(proficiencyRate ?? 0, 0), 1)
    }

    /// - Parameter difficulty: 指定すると、その難易度の問題だけで集計する(未指定はカテゴリ全体)
    static func calculate(
        records: [AnswerRecord],
        questions: [Question],
        category: WordCategory,
        difficulty: WordDifficulty? = nil
    ) -> CategoryProficiencySummary {
        let categoryQuestionsByID = questions.reduce(into: [String: Question]()) { result, question in
            guard question.category == category else { return }
            if let difficulty, question.difficulty != difficulty { return }
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
