import XCTest
@testable import HayaosiApp

final class QuestionSeederDistractorTests: XCTestCase {
    private static let fillerMeanings = ["補助候補一", "補助候補二"]

    func test_完全一致する意味要素を含む候補を除外する() throws {
        let correctMeaning = "含む"
        let candidateMeaning = "含む、中に入っている"
        let choices = try makeChoices(
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning
        )

        assertChoices(
            choices,
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            includesCandidate: false
        )
    }

    func test_先頭の意味要素が一致する候補を除外する() throws {
        let correctMeaning = "提供する"
        let candidateMeaning = "提供する、申し出る"
        let choices = try makeChoices(
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning
        )

        assertChoices(
            choices,
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            includesCandidate: false
        )
    }

    func test_カッコ外の表記が違う候補は除外しない() throws {
        let correctMeaning = "私（主格）"
        let candidateMeaning = "私の（所有格）"
        let choices = try makeChoices(
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            pos: .pronoun
        )

        assertChoices(
            choices,
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            includesCandidate: true
        )
    }

    func test_カッコ内の区切り文字では分割しない() throws {
        let correctMeaning = "あなた（主格・目的格）"
        let candidateMeaning = "それ（主格・目的格）"
        let choices = try makeChoices(
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            pos: .pronoun
        )

        assertChoices(
            choices,
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            includesCandidate: true
        )
    }

    func test_活用の違いは同一視しない() throws {
        let correctMeaning = "上がる"
        let candidateMeaning = "上げる、（お金を）集める"
        let choices = try makeChoices(
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning
        )

        assertChoices(
            choices,
            correctMeaning: correctMeaning,
            candidateMeaning: candidateMeaning,
            includesCandidate: true
        )
    }

    private func makeChoices(
        correctMeaning: String,
        candidateMeaning: String,
        pos: PartOfSpeech = .verb
    ) throws -> [String] {
        let entries = [
            makeEntry(id: "test_correct", meaning: correctMeaning, pos: pos),
            makeEntry(id: "test_filler_1", meaning: "補助候補一", pos: pos),
            makeEntry(id: "test_filler_2", meaning: "補助候補二", pos: pos),
            makeEntry(id: "test_candidate", meaning: candidateMeaning, pos: pos)
        ]
        let questions = QuestionSeeder.makeQuestions(from: entries)
        let question = try XCTUnwrap(questions.first { $0.id == "test_correct" })
        return question.choices
    }

    private func assertChoices(
        _ choices: [String],
        correctMeaning: String,
        candidateMeaning: String,
        includesCandidate: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expectedChoices = [correctMeaning] + Self.fillerMeanings
        if includesCandidate {
            expectedChoices.append(candidateMeaning)
        }
        XCTAssertEqual(Set(choices), Set(expectedChoices), file: file, line: line)
        XCTAssertEqual(choices.count, expectedChoices.count, file: file, line: line)
    }

    private func makeEntry(
        id: String,
        meaning: String,
        pos: PartOfSpeech
    ) -> WordEntry {
        WordEntry(
            id: id,
            word: id,
            meaning: meaning,
            pos: pos,
            category: .toeic,
            difficulty: .one
        )
    }
}
