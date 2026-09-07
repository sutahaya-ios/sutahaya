import XCTest
import SwiftData
@testable import HayaosiApp

final class ResultRecorderTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    func test_同じ日に複数回練習すると日別学習時間を累計する() throws {
        let context = ModelContext(container)
        let entry = makeEntry()
        let dayStart = Calendar.current.startOfDay(for: .now)
        let morning = Calendar.current.date(byAdding: .hour, value: 8, to: dayStart) ?? dayStart
        let evening = Calendar.current.date(byAdding: .hour, value: 20, to: dayStart) ?? dayStart

        ResultRecorder.record(
            entries: [entry],
            mode: .practice,
            elapsedSeconds: 60,
            recordedAt: morning,
            context: context
        )
        ResultRecorder.record(
            entries: [entry],
            mode: .practice,
            elapsedSeconds: 90,
            recordedAt: evening,
            context: context
        )

        let records = try context.fetch(FetchDescriptor<DailyStudyTime>())
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.dayStart, dayStart)
        XCTAssertEqual(record.categoryRaw, StudyCategory.juniorHigh.rawValue)
        XCTAssertEqual(record.totalSeconds, 150, accuracy: 0.001)
    }

    func test_日をまたいで練習すると別の日別レコードを作る() throws {
        let context = ModelContext(container)
        let entry = makeEntry()
        let firstDay = Calendar.current.startOfDay(for: .now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay

        ResultRecorder.record(
            entries: [entry],
            mode: .practice,
            elapsedSeconds: 60,
            recordedAt: firstDay,
            context: context
        )
        ResultRecorder.record(
            entries: [entry],
            mode: .practice,
            elapsedSeconds: 90,
            recordedAt: nextDay,
            context: context
        )

        let descriptor = FetchDescriptor<DailyStudyTime>(
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let records = try context.fetch(descriptor)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.dayStart), [firstDay, nextDay])
        XCTAssertEqual(records.map(\.totalSeconds), [60, 90])
    }

    private func makeEntry() -> QuizSession.Entry {
        let question = Question(
            id: "jh_0001",
            genre: .englishWord,
            type: .multipleChoice,
            text: "book",
            choices: ["本", "机", "椅子", "鉛筆"],
            answer: "本",
            category: .juniorHigh,
            difficulty: .one
        )
        return QuizSession.Entry(
            question: question,
            shuffledChoices: question.choices,
            selectedChoice: question.answer
        )
    }
}
