import Foundation
import SwiftData

/// カテゴリごとの日別学習時間
@Model
final class DailyStudyTime {
    /// "2026-08-12|junior_high" 形式。SwiftDataは複合ユニークキーを直接持てないため文字列で表現する
    @Attribute(.unique) var dayCategoryKey: String
    var dayStart: Date
    var categoryRaw: String
    var totalSeconds: Double

    init(
        dayStart: Date,
        category: WordCategory,
        totalSeconds: Double = 0,
        calendar: Calendar = .current
    ) {
        let normalizedDayStart = calendar.startOfDay(for: dayStart)
        self.dayCategoryKey = Self.makeDayCategoryKey(
            dayStart: normalizedDayStart,
            category: category,
            calendar: calendar
        )
        self.dayStart = normalizedDayStart
        self.categoryRaw = category.rawValue
        self.totalSeconds = totalSeconds
    }

    static func makeDayCategoryKey(
        dayStart: Date,
        category: WordCategory,
        calendar: Calendar = .current
    ) -> String {
        let normalizedDayStart = calendar.startOfDay(for: dayStart)
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: normalizedDayStart
        )
        let dateText = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(dateText)|\(category.rawValue)"
    }
}
