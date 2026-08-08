import Foundation

/// 解答履歴から、対戦タブに表示する今日の学習量と継続日数を集計する
struct LearningActivitySummary: Equatable {
    let todayAnswerCount: Int
    let streakDayCount: Int

    static func calculate(
        records: [AnswerRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> LearningActivitySummary {
        calculate(
            answerDates: records.map(\.answeredAt),
            now: now,
            calendar: calendar
        )
    }

    static func calculate(
        answerDates: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> LearningActivitySummary {
        let today = calendar.startOfDay(for: now)
        let todayAnswerCount = answerDates.filter { calendar.isDate($0, inSameDayAs: now) }.count
        let answeredDays = Set(answerDates.map { calendar.startOfDay(for: $0) })
            .filter { $0 <= today }

        guard let lastAnsweredDay = answeredDays.max(),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              lastAnsweredDay == today || lastAnsweredDay == yesterday else {
            return LearningActivitySummary(todayAnswerCount: todayAnswerCount, streakDayCount: 0)
        }

        var streakDayCount = 0
        var currentDay: Date? = lastAnsweredDay
        while let day = currentDay, answeredDays.contains(day) {
            streakDayCount += 1
            currentDay = calendar.date(byAdding: .day, value: -1, to: day)
        }

        return LearningActivitySummary(
            todayAnswerCount: todayAnswerCount,
            streakDayCount: streakDayCount
        )
    }
}
