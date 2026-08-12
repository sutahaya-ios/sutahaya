import Foundation

/// 復習項目を、存在する問題と任意のカテゴリで絞り込む
struct ReviewListFilter {
    static func filter(
        reviewItems: [ReviewItem],
        questions: [Question],
        category: WordCategory?
    ) -> [ReviewItem] {
        let questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })

        return reviewItems.filter { item in
            guard let question = questionsByID[item.questionID] else { return false }
            return category == nil || question.category == category
        }
    }
}
