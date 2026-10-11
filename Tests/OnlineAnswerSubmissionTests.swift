import XCTest
@testable import HayaosiApp

final class OnlineAnswerSubmissionTests: XCTestCase {
    func test_表示問題と現在問題が同じなら表示問題へ回答する() {
        let displayed = DisplayedQuestionContext(questionID: "question-n", questionIndex: 2)

        let submission = OnlineAnswerSubmission.make(
            choice: "正解",
            visibleCount: 3,
            displayedQuestion: displayed,
            currentQuestionID: "question-n",
            currentQuestionIndex: 2
        )

        XCTAssertEqual(submission, OnlineAnswerSubmission(
            questionIndex: 2,
            choice: "正解",
            visibleCount: 3
        ))
    }

    func test_submit前に次問題へ進んだ回答は生成しない() {
        let displayed = DisplayedQuestionContext(questionID: "question-n", questionIndex: 2)

        let submission = OnlineAnswerSubmission.make(
            choice: "question-nの正解",
            visibleCount: 4,
            displayedQuestion: displayed,
            currentQuestionID: "question-n-plus-1",
            currentQuestionIndex: 3
        )

        XCTAssertNil(submission, "前問題の選択肢を次問題の回答として送ってはいけない")
    }

    func test_indexが同じでもquestionIDが異なる回答は生成しない() {
        let displayed = DisplayedQuestionContext(questionID: "old-generation", questionIndex: 0)

        let submission = OnlineAnswerSubmission.make(
            choice: "古い問題の正解",
            visibleCount: 2,
            displayedQuestion: displayed,
            currentQuestionID: "new-generation",
            currentQuestionIndex: 0
        )

        XCTAssertNil(submission)
    }

    func test_切替後の新しい問題は新しいcontextで回答できる() {
        let displayed = DisplayedQuestionContext(questionID: "question-n-plus-1", questionIndex: 3)

        let submission = OnlineAnswerSubmission.make(
            choice: "次問題の正解",
            visibleCount: 1,
            displayedQuestion: displayed,
            currentQuestionID: "question-n-plus-1",
            currentQuestionIndex: 3
        )

        XCTAssertEqual(submission?.questionIndex, 3)
        XCTAssertEqual(submission?.choice, "次問題の正解")
    }

    func test_連続問題で前問題のcontextを再利用しない() {
        let previous = DisplayedQuestionContext(questionID: "question-0", questionIndex: 0)
        let current = DisplayedQuestionContext(questionID: "question-1", questionIndex: 1)

        XCTAssertNil(OnlineAnswerSubmission.make(
            choice: "前問題の正解",
            visibleCount: 4,
            displayedQuestion: previous,
            currentQuestionID: current.questionID,
            currentQuestionIndex: current.questionIndex
        ))
        XCTAssertNotNil(OnlineAnswerSubmission.make(
            choice: "現在問題の正解",
            visibleCount: 2,
            displayedQuestion: current,
            currentQuestionID: current.questionID,
            currentQuestionIndex: current.questionIndex
        ))
    }
}
