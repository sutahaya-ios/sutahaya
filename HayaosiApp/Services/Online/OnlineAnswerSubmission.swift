/// RTDBへ送る回答のうち、端末側で確定できる値。
struct OnlineAnswerSubmission: Equatable {
    let questionIndex: Int
    let choice: String
    let visibleCount: Int

    static func make(
        choice: String,
        visibleCount: Int,
        displayedQuestion: DisplayedQuestionContext,
        currentQuestionID: String,
        currentQuestionIndex: Int
    ) -> OnlineAnswerSubmission? {
        guard displayedQuestion.questionID == currentQuestionID,
              displayedQuestion.questionIndex == currentQuestionIndex else {
            return nil
        }

        return OnlineAnswerSubmission(
            questionIndex: displayedQuestion.questionIndex,
            choice: choice,
            visibleCount: visibleCount
        )
    }
}
