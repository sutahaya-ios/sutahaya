import Foundation

/// 日別学習時間を直近12週の描画データへ変換する
struct StudyTimeHeatmap {
    static let weekCount = 12
    static let daysPerWeek = 7

    enum Level: Int, CaseIterable, Equatable {
        case none
        case low
        case medium
        case high
        case highest
    }

    struct DayCell: Equatable {
        let date: Date
        let totalSeconds: Double
        let level: Level
    }

    struct Summary: Equatable {
        let weeks: [[DayCell?]]
        let totalSeconds: Double
    }

    private enum Thresholds {
        static let level2Seconds: Double = 10 * 60
        static let level3Seconds: Double = 20 * 60
        static let level4Seconds: Double = 35 * 60
    }

    /// `category` に nil を渡すと全カテゴリを合算する
    static func calculate(
        records: [DailyStudyTime],
        category: StudyCategory?,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Summary {
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let currentWeekStart = calendar.date(
            byAdding: .day,
            value: 1 - weekday,
            to: today
        ) ?? today
        let gridStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(weekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart

        let secondsByDay = records.reduce(into: [Date: Double]()) { result, record in
            if let category, record.categoryRaw != category.rawValue { return }
            let dayStart = calendar.startOfDay(for: record.dayStart)
            result[dayStart, default: 0] += max(record.totalSeconds, 0)
        }

        var includedTotalSeconds = 0.0
        let weeks: [[DayCell?]] = (0..<weekCount).map { weekIndex in
            (0..<daysPerWeek).map { dayIndex in
                let dayOffset = weekIndex * daysPerWeek + dayIndex
                let date = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: gridStart
                ) ?? gridStart
                guard date <= today else { return nil }
                let totalSeconds = secondsByDay[date, default: 0]
                includedTotalSeconds += totalSeconds
                return DayCell(
                    date: date,
                    totalSeconds: totalSeconds,
                    level: level(for: totalSeconds)
                )
            }
        }

        return Summary(weeks: weeks, totalSeconds: includedTotalSeconds)
    }

    private static func level(for totalSeconds: Double) -> Level {
        guard totalSeconds > 0 else { return .none }
        if totalSeconds < Thresholds.level2Seconds {
            return .low
        }
        if totalSeconds < Thresholds.level3Seconds {
            return .medium
        }
        if totalSeconds < Thresholds.level4Seconds {
            return .high
        }
        return .highest
    }
}
