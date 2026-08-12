import XCTest
@testable import HayaosiApp

final class CategoryProficiencySummaryTests: XCTestCase {
    func test_指定カテゴリの習得率と難易度別正答率を集計する() throws {
        let questions = [
            makeQuestion(id: "jh_0001", category: .juniorHigh, difficulty: .one),
            makeQuestion(id: "jh_0002", category: .juniorHigh, difficulty: .one),
            makeQuestion(id: "jh_0003", category: .juniorHigh, difficulty: .two),
            makeQuestion(id: "hs_0001", category: .highSchool, difficulty: .one)
        ]
        let records = [
            AnswerRecord(questionID: "jh_0001", isCorrect: true, mode: .practice),
            AnswerRecord(questionID: "jh_0001", isCorrect: false, mode: .practice),
            AnswerRecord(questionID: "jh_0002", isCorrect: true, mode: .practice),
            AnswerRecord(questionID: "jh_0003", isCorrect: false, mode: .practice),
            AnswerRecord(questionID: "hs_0001", isCorrect: true, mode: .practice)
        ]

        let summary = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: .juniorHigh
        )

        XCTAssertEqual(summary.totalWordCount, 3)
        XCTAssertEqual(summary.masteredWordCount, 2)
        XCTAssertEqual(try XCTUnwrap(summary.proficiencyRate), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.accuracy(for: .one)), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.accuracy(for: .two)), 0, accuracy: 0.001)
        XCTAssertNil(summary.accuracy(for: .three))
    }

    func test_解答がなければ習得率は0になる() throws {
        let summary = CategoryProficiencySummary.calculate(
            records: [],
            questions: [makeQuestion(id: "jh_0001", category: .juniorHigh, difficulty: .one)],
            category: .juniorHigh
        )

        XCTAssertEqual(summary.totalWordCount, 1)
        XCTAssertEqual(summary.masteredWordCount, 0)
        XCTAssertEqual(try XCTUnwrap(summary.proficiencyRate), 0, accuracy: 0.001)
        XCTAssertTrue(WordDifficulty.allCases.allSatisfy { summary.accuracy(for: $0) == nil })
    }

    func test_存在しない問題IDの履歴を無視する() throws {
        let summary = CategoryProficiencySummary.calculate(
            records: [
                AnswerRecord(questionID: "removed_id", isCorrect: true, mode: .practice),
                AnswerRecord(questionID: "jh_0001", isCorrect: false, mode: .practice)
            ],
            questions: [makeQuestion(id: "jh_0001", category: .juniorHigh, difficulty: .one)],
            category: .juniorHigh
        )

        XCTAssertEqual(summary.totalWordCount, 1)
        XCTAssertEqual(summary.masteredWordCount, 0)
        XCTAssertEqual(try XCTUnwrap(summary.proficiencyRate), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.accuracy(for: .one)), 0, accuracy: 0.001)
    }

    private func makeQuestion(
        id: String,
        category: WordCategory,
        difficulty: WordDifficulty
    ) -> Question {
        Question(
            id: id,
            genre: .englishWord,
            type: .multipleChoice,
            text: id,
            choices: ["正解", "誤答1", "誤答2", "誤答3"],
            answer: "正解",
            category: category,
            difficulty: difficulty
        )
    }
}
