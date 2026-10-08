import XCTest
@testable import HayaosiApp

final class CompetitiveMatchmakingModelsTests: XCTestCase {
    func test_WAITING_PLAYERSだけPhaseA2Sessionへ変換できる() throws {
        let projection = try XCTUnwrap(CompetitiveMatchmakingProjection(databaseValue: [
            "uid": "player-1",
            "state": "WAITING_PLAYERS",
            "sessionId": "session-1",
            "sessionEpoch": 3,
            "protocolVersion": CompetitiveService.protocolVersion,
            "matchId": "match-1",
            "assignmentTicket": "ticket-1",
            "updatedAtEpochMs": 1_000
        ]))

        XCTAssertEqual(projection.state, .waitingPlayers)
        XCTAssertEqual(projection.competitiveSession, CompetitiveSession(
            matchId: "match-1",
            sessionId: "session-1",
            sessionEpoch: 3,
            assignmentTicket: "ticket-1"
        ))
    }

    func test_QUEUE中はMatchSessionを作らない() throws {
        let projection = try XCTUnwrap(CompetitiveMatchmakingProjection(databaseValue: [
            "uid": "player-1",
            "state": "QUEUED",
            "sessionId": "session-1",
            "sessionEpoch": 1,
            "protocolVersion": CompetitiveService.protocolVersion,
            "queuedAtEpochMs": 900,
            "updatedAtEpochMs": 1_000
        ]))

        XCTAssertNil(projection.competitiveSession)
    }

    func test_MatchmakingAckを型付きで復元する() throws {
        let ack = try XCTUnwrap(CompetitiveMatchmakingAck(value: [
            "intentId": "intent-1",
            "status": "ACCEPTED",
            "retryable": false,
            "sessionId": "session-1",
            "sessionEpoch": 2,
            "matchmakingState": "MATCH_FOUND",
            "matchId": "match-1",
            "assignmentTicket": "ticket-1"
        ]))

        XCTAssertEqual(ack.status, .accepted)
        XCTAssertEqual(ack.matchmakingState, .matchFound)
        XCTAssertEqual(ack.matchId, "match-1")
        XCTAssertEqual(ack.assignmentTicket, "ticket-1")
    }
}
