import XCTest
@testable import HayaosiApp

/// 端末のローカル日付を基準に、今日の学習量と継続日数が正しく集計されることを確認する
final class LearningActivitySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    private func date(dayOffset: Int, hour: Int = 12) throws -> Date {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 8,
            hour: hour
        )))
        return try XCTUnwrap(calendar.date(byAdding: .day, value: dayOffset, to: base))
    }

    func test_今日だけ解答すると今日1問で連続1日になる() throws {
        let now = try date(dayOffset: 0)

        let summary = LearningActivitySummary.calculate(
            answerDates: [try date(dayOffset: 0, hour: 1)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.todayAnswerCount, 1)
        XCTAssertEqual(summary.streakDayCount, 1)
    }

    func test_今日を含む3日連続を数える() throws {
        let now = try date(dayOffset: 0)
        let dates = try [0, -1, -2].map { try date(dayOffset: $0) }

        let summary = LearningActivitySummary.calculate(answerDates: dates, now: now, calendar: calendar)

        XCTAssertEqual(summary.todayAnswerCount, 1)
        XCTAssertEqual(summary.streakDayCount, 3)
    }

    func test_昨日まで連続なら今日は未解答でも継続日数を保つ() throws {
        let now = try date(dayOffset: 0)
        let dates = try [-1, -2, -3].map { try date(dayOffset: $0) }

        let summary = LearningActivitySummary.calculate(answerDates: dates, now: now, calendar: calendar)

        XCTAssertEqual(summary.todayAnswerCount, 0)
        XCTAssertEqual(summary.streakDayCount, 3)
    }

    func test_最終解答が一昨日なら連続0日になる() throws {
        let now = try date(dayOffset: 0)

        let summary = LearningActivitySummary.calculate(
            answerDates: [try date(dayOffset: -2)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.todayAnswerCount, 0)
        XCTAssertEqual(summary.streakDayCount, 0)
    }

    func test_記録がなければ両方0になる() throws {
        let summary = LearningActivitySummary.calculate(
            answerDates: [],
            now: try date(dayOffset: 0),
            calendar: calendar
        )

        XCTAssertEqual(summary.todayAnswerCount, 0)
        XCTAssertEqual(summary.streakDayCount, 0)
    }

    func test_同じ日に複数回答しても連続日数は1日として数える() throws {
        let now = try date(dayOffset: 0)
        let dates = try [1, 8, 20].map { try date(dayOffset: 0, hour: $0) }

        let summary = LearningActivitySummary.calculate(answerDates: dates, now: now, calendar: calendar)

        XCTAssertEqual(summary.todayAnswerCount, 3)
        XCTAssertEqual(summary.streakDayCount, 1)
    }
}
