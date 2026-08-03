import XCTest
import SwiftData
@testable import HayaosiApp

/// 出題エンジンのテスト。練習・対戦の両方がこのエンジンに乗るため、
/// フェーズ遷移(回答受付 → 正誤表示 → 次の問題)の壊れに早く気付けるようにする
final class QuizSessionTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Question.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    // MARK: - ヘルパー

    /// 「q1 → 正答a1」「q2 → 正答a2」… の問題を作る
    private func makeQuestions(count: Int) throws -> [Question] {
        let context = ModelContext(container)
        return (1...count).map { index in
            let question = Question(
                id: "q\(index)",
                genre: .englishWord,
                type: .multipleChoice,
                style: .speed,
                text: "q\(index)",
                choices: ["a\(index)", "wrong1", "wrong2", "wrong3"],
                answer: "a\(index)"
            )
            context.insert(question)
            return question
        }
    }

    private func makeSession(count: Int, timeLimit: TimeInterval = 20) throws -> QuizSession {
        QuizSession(questions: try makeQuestions(count: count), timeLimit: timeLimit)
    }

    // MARK: - 正誤判定

    func test_正解を選ぶと正誤表示に移り正答数が増える() throws {
        let session = try makeSession(count: 2)

        session.select("a1")

        XCTAssertEqual(session.phase, .feedback)
        XCTAssertEqual(session.correctCount, 1)
        XCTAssertEqual(session.wrongCount, 1, "未回答の残り1問は不正解として数える")
        XCTAssertEqual(session.currentEntry?.selectedChoice, "a1")
    }

    func test_不正解を選ぶと正答数が増えない() throws {
        let session = try makeSession(count: 1)

        session.select("wrong1")

        XCTAssertEqual(session.phase, .feedback)
        XCTAssertEqual(session.correctCount, 0)
        XCTAssertEqual(session.wrongCount, 1)
    }

    func test_正誤表示中の選択は無視される() throws {
        let session = try makeSession(count: 1)

        session.select("wrong1")
        session.select("a1")

        XCTAssertEqual(session.currentEntry?.selectedChoice, "wrong1", "回答は上書きできない")
        XCTAssertEqual(session.correctCount, 0)
    }

    // MARK: - 制限時間

    func test_制限時間を過ぎると時間切れで正誤表示に移る() throws {
        let session = try makeSession(count: 1, timeLimit: 10)

        session.tick(4)
        XCTAssertEqual(session.remainingTime, 6)
        XCTAssertEqual(session.phase, .answering)

        session.tick(6)

        XCTAssertEqual(session.remainingTime, 0)
        XCTAssertEqual(session.phase, .feedback)
        XCTAssertEqual(session.currentEntry?.didTimeout, true)
        XCTAssertEqual(session.correctCount, 0)
    }

    func test_残り時間はマイナスにならない() throws {
        let session = try makeSession(count: 1, timeLimit: 10)

        session.tick(99)

        XCTAssertEqual(session.remainingTime, 0)
    }

    // MARK: - 問題送り

    func test_次の問題へ進むと残り時間がリセットされる() throws {
        let session = try makeSession(count: 2, timeLimit: 20)

        session.tick(5)
        session.select("a1")
        session.advance()

        XCTAssertEqual(session.phase, .answering)
        XCTAssertEqual(session.remainingTime, 20)
        XCTAssertEqual(session.currentEntry?.question.id, "q2")
    }

    func test_回答受付中に進もうとしても無視される() throws {
        let session = try makeSession(count: 2)

        session.advance()

        XCTAssertEqual(session.currentEntry?.question.id, "q1")
        XCTAssertEqual(session.phase, .answering)
    }

    func test_最終問題の次は終了になる() throws {
        let session = try makeSession(count: 2)

        session.select("a1")
        session.advance()
        XCTAssertTrue(session.isLastQuestion)

        session.select("a2")
        session.advance()

        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.correctCount, 2)
        XCTAssertEqual(session.wrongCount, 0)
    }

    func test_問題が空なら最初から終了状態() {
        let session = QuizSession(questions: [], timeLimit: 20)

        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.totalCount, 0)
        XCTAssertNil(session.currentEntry)
    }

    // MARK: - 選択肢

    func test_選択肢はシャッフルされても正答を含む() throws {
        let session = try makeSession(count: 1)

        let choices = session.currentEntry?.shuffledChoices ?? []

        XCTAssertEqual(choices.count, 4)
        XCTAssertEqual(Set(choices), ["a1", "wrong1", "wrong2", "wrong3"])
    }
}
