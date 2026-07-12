import Foundation
import SwiftData

/// 復習リスト(要件 §8.1)。間違えた問題が登録され、正解すると外れる
@Model
final class ReviewItem {
    @Attribute(.unique) var questionID: String
    var wrongCount: Int
    var lastAskedAt: Date

    init(questionID: String, wrongCount: Int = 1, lastAskedAt: Date = .now) {
        self.questionID = questionID
        self.wrongCount = wrongCount
        self.lastAskedAt = lastAskedAt
    }
}
