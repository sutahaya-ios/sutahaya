import XCTest
@testable import HayaosiApp

final class QuestionSetTests: XCTestCase {
    func test_3形式を混ぜた問題集を保存用に正規化する() throws {
        let draft = QuestionSetDraft(
            id: "set-1",
            title: " \n日本の地理\t ",
            questions: [trueFalse(), multipleChoice(), shortAnswer()]
        )

        let validated = try draft.validated()

        XCTAssertEqual(validated.id, "set-1")
        XCTAssertEqual(validated.title, "日本の地理")
        XCTAssertEqual(validated.questions.map(\.format), [.trueFalse, .multipleChoice, .shortAnswer])
        XCTAssertEqual(validated.questions.map(\.id), draft.questions.map(\.id))
        XCTAssertEqual(draft.title, " \n日本の地理\t ", "正規化は入力中の元データを変更しない")
    }

    func test_前後空白を除去して選択肢と正解を照合する() throws {
        var question = multipleChoice()
        question.text = " \n日本の首都は？\t "
        question.choices = [" 東京 ", "\n大阪", "京都\t", "札幌"]
        question.answers = ["\t東京\n"]
        question.explanation = " \n首都は東京です。\t "

        let validated = try question.validated()

        XCTAssertEqual(validated.text, "日本の首都は？")
        XCTAssertEqual(validated.choices, ["東京", "大阪", "京都", "札幌"])
        XCTAssertEqual(validated.answers, ["東京"])
        XCTAssertEqual(validated.explanation, "首都は東京です。")
    }

    func test_タイトルは空白を除いた1文字から80文字まで() throws {
        for title in ["あ", String(repeating: "あ", count: 80)] {
            let draft = QuestionSetDraft(title: " \(title)\n", questions: [trueFalse()])
            XCTAssertEqual(try draft.validated().title, title)
        }
        for title in ["", " \n\t　", String(repeating: "あ", count: 81)] {
            assertInvalid(QuestionSetDraft(title: title, questions: [trueFalse()]))
        }
    }

    func test_問題数は1問から20問まで() throws {
        for count in [1, 20] {
            let questions = (0..<count).map { trueFalse(id: "question-\($0)") }
            let draft = QuestionSetDraft(title: "問題集", questions: questions)
            XCTAssertEqual(try draft.validated().questions.count, count)
        }
        for count in [0, 21] {
            let questions = (0..<count).map { trueFalse(id: "question-\($0)") }
            assertInvalid(QuestionSetDraft(title: "問題集", questions: questions))
        }
    }

    func test_問題IDが重複する問題集を拒否する() {
        assertInvalid(QuestionSetDraft(
            title: "問題集",
            questions: [trueFalse(id: "same-id"), shortAnswer(id: "same-id")]
        ))
    }

    func test_問題集と問題の不正な識別子を拒否する() {
        for id in ["", "parent/child", String(repeating: "a", count: 129)] {
            assertInvalid(QuestionSetDraft(id: id, title: "問題集", questions: [trueFalse()]))
            assertInvalid(trueFalse(id: id))
        }
    }

    func test_問題集内の不正な問題も検証する() {
        var invalid = shortAnswer()
        invalid.answers = []
        assertInvalid(QuestionSetDraft(title: "問題集", questions: [trueFalse(), invalid]))
    }

    func test_問題文は空白を除いた1文字から2000文字まで() throws {
        for text in ["問", String(repeating: "問", count: 2_000)] {
            var question = trueFalse()
            question.text = "\n\(text) "
            XCTAssertEqual(try question.validated().text, text)
        }
        for text in ["", " \n\t　", String(repeating: "問", count: 2_001)] {
            var question = trueFalse()
            question.text = text
            assertInvalid(question)
        }
    }

    func test_解説は任意で4000文字まで() throws {
        for explanation in ["", " \n\t　", String(repeating: "説", count: 4_000)] {
            var question = trueFalse()
            question.explanation = explanation
            XCTAssertNoThrow(try question.validated())
        }
        var question = trueFalse()
        question.explanation = String(repeating: "説", count: 4_001)
        assertInvalid(question)
    }

    func test_丸バツはそれぞれ単一の正解として保存できる() throws {
        for answer in ["○", "×"] {
            var question = trueFalse()
            question.answers = [answer]
            XCTAssertEqual(try question.validated().answers, [answer])
        }
    }

    func test_丸バツの選択肢と単一正解を強制する() {
        for choices in [[], ["○"], ["×", "○"], ["○", "×", "不明"]] {
            var question = trueFalse()
            question.choices = choices
            assertInvalid(question)
        }
        for answers in [[], ["○", "×"], ["正しい"], [" \n"]] {
            var question = trueFalse()
            question.answers = answers
            assertInvalid(question)
        }
    }

    func test_4択は空白除去後に異なる4つの選択肢が必要() {
        let invalidChoices = [
            ["東京", "大阪", "京都"],
            ["東京", "大阪", "京都", "札幌", "仙台"],
            ["東京", "大阪", "京都", ""],
            ["東京", "大阪", "京都", " \n　"],
            ["東京", "大阪", "京都", " 東京\n"]
        ]
        for choices in invalidChoices {
            var question = multipleChoice()
            question.choices = choices
            assertInvalid(question)
        }
    }

    func test_4択の選択肢は200文字まで() throws {
        let boundaryChoice = String(repeating: "選", count: 200)
        var question = multipleChoice()
        question.choices[3] = boundaryChoice
        question.answers = [boundaryChoice]
        XCTAssertEqual(try question.validated().answers, [boundaryChoice])

        question.choices[3] += "択"
        question.answers = ["東京"]
        assertInvalid(question)
        question.answers = [question.choices[3]]
        assertInvalid(question)
    }

    func test_4択の正解は選択肢内の1つだけ() {
        for answers in [[], ["東京", "大阪"], ["仙台"], [" \n"]] {
            var question = multipleChoice()
            question.answers = answers
            assertInvalid(question)
        }
    }

    func test_短文は1個から5個の正解候補を保存できる() throws {
        for answers in [["東京"], ["東京", "東京都", "とうきょう", "Tokyo", "TOKYO"]] {
            var question = shortAnswer()
            question.answers = answers.map { " \($0)\n" }
            XCTAssertEqual(try question.validated().answers, answers)
        }
    }

    func test_短文の空欄と重複と過剰な候補と選択肢を拒否する() {
        let invalidAnswers = [
            [String](),
            [""],
            ["東京", " \n　"],
            ["東京", " 東京\n"],
            ["東京", "東京都", "とうきょう", "Tokyo", "TOKYO", "tokyo"]
        ]
        for answers in invalidAnswers {
            var question = shortAnswer()
            question.answers = answers
            assertInvalid(question)
        }
        var question = shortAnswer()
        question.choices = ["東京"]
        assertInvalid(question)
    }

    func test_短文の正解候補は各200文字まで() throws {
        var question = shortAnswer()
        let answer = String(repeating: "答", count: 200)
        question.answers = [answer]
        XCTAssertEqual(try question.validated().answers, [answer])

        question.answers = ["東京", answer + "案"]
        assertInvalid(question)
    }

    func test_永続化した問題集を識別子と状態を保って復元する() throws {
        let draft = try QuestionSetDraft(
            id: "set-roundtrip",
            title: "日本の地理",
            questions: [trueFalse(), multipleChoice(), shortAnswer()]
        ).validated()
        for status in [QuestionSetStatus.active, .blocked, .deleted] {
            let original = QuestionSet(
                id: draft.id,
                title: draft.title,
                creatorUID: "author-uid",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                questions: draft.questions,
                status: status
            )
            let data = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(QuestionSet.self, from: data)

            XCTAssertEqual(restored, original)
            XCTAssertEqual(restored.schemaVersion, 1)
            XCTAssertEqual(restored.questions.map(\.format.rawValue), ["trueFalse", "multipleChoice", "shortAnswer"])
        }
    }

    private func trueFalse(id: String = "true-false") -> AuthoredQuestion {
        AuthoredQuestion(id: id, format: .trueFalse, text: "日本の首都は東京である。", choices: ["○", "×"], answers: ["○"])
    }

    private func multipleChoice() -> AuthoredQuestion {
        AuthoredQuestion(id: "multiple-choice", format: .multipleChoice, text: "日本の首都は？", choices: ["東京", "大阪", "京都", "札幌"], answers: ["東京"])
    }

    private func shortAnswer(id: String = "short-answer") -> AuthoredQuestion {
        AuthoredQuestion(id: id, format: .shortAnswer, text: "日本の首都は？", choices: [], answers: ["東京", "東京都"])
    }

    private func assertInvalid(_ question: AuthoredQuestion, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try question.validated(), file: file, line: line) { error in
            XCTAssertTrue(error is QuestionSetValidationError, file: file, line: line)
        }
    }

    private func assertInvalid(_ draft: QuestionSetDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try draft.validated(), file: file, line: line) { error in
            XCTAssertTrue(error is QuestionSetValidationError, file: file, line: line)
        }
    }
}
