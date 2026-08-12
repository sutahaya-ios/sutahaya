import XCTest
@testable import HayaosiApp

final class StudyTimeHeatmapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func test_記録がないとき全マスがレベル0で合計も0になる() throws {
        let referenceDate = try makeDate(year: 2026, month: 8, day: 12)

        let summary = StudyTimeHeatmap.calculate(
            records: [],
            category: .juniorHigh,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.weeks.count, 12)
        XCTAssertTrue(summary.weeks.allSatisfy { $0.count == 7 })
        XCTAssertTrue(
            summary.weeks
                .flatMap { $0 }
                .compactMap { $0 }
                .allSatisfy { $0.level == .none }
        )
        XCTAssertEqual(summary.totalSeconds, 0)
    }

    func test_今日より後のマスは存在しない() throws {
        let referenceDate = try makeDate(year: 2026, month: 8, day: 12)

        let summary = StudyTimeHeatmap.calculate(
            records: [],
            category: .juniorHigh,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let latestWeek = try XCTUnwrap(summary.weeks.last)

        XCTAssertTrue(latestWeek[0...3].allSatisfy { $0 != nil })
        XCTAssertNil(latestWeek[4])
        XCTAssertNil(latestWeek[5])
        XCTAssertNil(latestWeek[6])
    }

    func test_しきい値の境界でレベルが変わる() throws {
        let referenceDate = try makeDate(year: 2026, month: 8, day: 12)
        let testCases: [(dayOffset: Int, seconds: Double, expectedLevel: StudyTimeHeatmap.Level)] = [
            (-4, 9 * 60, .low),
            (-3, 10 * 60, .medium),
            (-2, 34 * 60, .high),
            (-1, 35 * 60, .highest)
        ]
        let records = testCases.map { testCase in
            let date = calendar.date(
                byAdding: .day,
                value: testCase.dayOffset,
                to: referenceDate
            ) ?? referenceDate
            return DailyStudyTime(
                dayStart: date,
                category: .juniorHigh,
                totalSeconds: testCase.seconds,
                calendar: calendar
            )
        }

        let summary = StudyTimeHeatmap.calculate(
            records: records,
            category: .juniorHigh,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let days = summary.weeks.flatMap { $0 }.compactMap { $0 }

        for testCase in testCases {
            let expectedDate = calendar.date(
                byAdding: .day,
                value: testCase.dayOffset,
                to: referenceDate
            ) ?? referenceDate
            let day = try XCTUnwrap(days.first { calendar.isDate($0.date, inSameDayAs: expectedDate) })
            XCTAssertEqual(day.level, testCase.expectedLevel)
        }
    }

    private func makeDate(year: Int, month: Int, day: Int) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        )
    }
}
