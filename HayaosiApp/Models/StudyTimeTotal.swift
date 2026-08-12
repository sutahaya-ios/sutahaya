import Foundation
import SwiftData

/// カテゴリごとの累計学習時間。セッション履歴は必要になるまで保持しない
@Model
final class StudyTimeTotal {
    @Attribute(.unique) var categoryRaw: String
    var totalSeconds: Double

    init(categoryRaw: String, totalSeconds: Double = 0) {
        self.categoryRaw = categoryRaw
        self.totalSeconds = totalSeconds
    }

    convenience init(category: WordCategory, totalSeconds: Double = 0) {
        self.init(categoryRaw: category.rawValue, totalSeconds: totalSeconds)
    }
}
