import Foundation
import XCTest
@testable import HayaosiApp

final class CompetitiveScoringParityTests: XCTestCase {
    func test_CompetitiveBackendの代表配点が現行BattleScoringと一致する() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/competitive-v2-scoring.json")
        let fixture = try JSONDecoder().decode(
            ScoringFixture.self,
            from: Data(contentsOf: fixtureURL)
        )

        for testCase in fixture.cases {
            let answers = testCase.answers.map { answer in
                RoomState.Answer(
                    uid: answer.uid,
                    questionIndex: 0,
                    choice: answer.answer,
                    answeredAtMS: answer.timestamp,
                    visibleCount: 1
                )
            }
            let result = BattleScoring.result(
                answers: answers,
                correctAnswer: fixture.correctAnswer,
                participantIDs: fixture.participantOrder
            )

            XCTAssertEqual(result.correctIDs, testCase.correctUIDs, testCase.name)
            XCTAssertEqual(result.wrongIDs, Set(testCase.wrongUIDs), testCase.name)
            let normalizedChanges = Dictionary(uniqueKeysWithValues: fixture.participantOrder.map {
                ($0, result.pointChanges[$0] ?? 0)
            })
            XCTAssertEqual(normalizedChanges, testCase.scoreDeltas, testCase.name)
        }
    }
}

private struct ScoringFixture: Decodable {
    let participantOrder: [String]
    let correctAnswer: String
    let cases: [ScoringCase]
}

private struct ScoringCase: Decodable {
    let name: String
    let answers: [ScoringAnswer]
    let correctUIDs: [String]
    let wrongUIDs: [String]
    let scoreDeltas: [String: Int]
}

private struct ScoringAnswer: Decodable {
    let uid: String
    let answer: String
    let timestamp: Double
}
