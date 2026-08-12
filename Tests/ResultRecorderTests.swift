import XCTest
import SwiftData
@testable import HayaosiApp

final class ResultRecorderTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([Question.self, AnswerRecord.self, ReviewItem.self, StudyTimeTotal.self])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    func test_同じカテゴリで複数回練習すると学習時間を累計する() throws {
        let context = ModelContext(container)
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
        let entry = QuizSession.Entry(
            question: question,
            shuffledChoices: question.choices,
            selectedChoice: question.answer
        )

        ResultRecorder.record(entries: [entry], mode: .practice, elapsedSeconds: 60, context: context)
        ResultRecorder.record(entries: [entry], mode: .practice, elapsedSeconds: 90, context: context)

        let totals = try context.fetch(FetchDescriptor<StudyTimeTotal>())
        let total = try XCTUnwrap(totals.first)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(total.categoryRaw, WordCategory.juniorHigh.rawValue)
        XCTAssertEqual(total.totalSeconds, 150, accuracy: 0.001)
    }
}
