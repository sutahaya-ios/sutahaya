import XCTest
@testable import HayaosiApp

final class ReviewListFilterTests: XCTestCase {
    func test_指定カテゴリの復習項目だけを返す() {
        let juniorHighQuestion = makeQuestion(id: "jh_0001", category: .juniorHigh)
        let highSchoolQuestion = makeQuestion(id: "hs_0001", category: .highSchool)
        let items = [
            ReviewItem(questionID: juniorHighQuestion.id),
            ReviewItem(questionID: highSchoolQuestion.id)
        ]

        let result = ReviewListFilter.filter(
            reviewItems: items,
            questions: [juniorHighQuestion, highSchoolQuestion],
            category: .juniorHigh
        )

        XCTAssertEqual(result.map(\.questionID), [juniorHighQuestion.id])
    }

    func test_カテゴリ指定なしなら全カテゴリを返す() {
        let questions = [
            makeQuestion(id: "jh_0001", category: .juniorHigh),
            makeQuestion(id: "hs_0001", category: .highSchool)
        ]
        let items = questions.map { ReviewItem(questionID: $0.id) }

        let result = ReviewListFilter.filter(
            reviewItems: items,
            questions: questions,
            category: nil
        )

        XCTAssertEqual(result.map(\.questionID), items.map(\.questionID))
    }

    func test_該当する問題がない復習項目を除外する() {
        let validQuestion = makeQuestion(id: "jh_0001", category: .juniorHigh)
        let items = [
            ReviewItem(questionID: "removed_id"),
            ReviewItem(questionID: validQuestion.id)
        ]

        let result = ReviewListFilter.filter(
            reviewItems: items,
            questions: [validQuestion],
            category: nil
        )

        XCTAssertEqual(result.map(\.questionID), [validQuestion.id])
    }

    func test_指定した問題IDだけを今回の復習として返す() {
        let questions = [
            makeQuestion(id: "jh_0001", category: .juniorHigh),
            makeQuestion(id: "jh_0002", category: .juniorHigh),
            makeQuestion(id: "hs_0001", category: .highSchool)
        ]
        let items = questions.map { ReviewItem(questionID: $0.id) }

        let result = ReviewListFilter.filter(
            reviewItems: items,
            questions: questions,
            category: nil,
            questionIDs: ["jh_0002", "hs_0001"]
        )

        XCTAssertEqual(result.map(\.questionID), ["jh_0002", "hs_0001"])
    }

    private func makeQuestion(id: String, category: WordCategory) -> Question {
        Question(
            id: id,
            genre: .englishWord,
            type: .multipleChoice,
            text: id,
            choices: ["正解", "誤答1", "誤答2", "誤答3"],
            answer: "正解",
            category: category
        )
    }
}
