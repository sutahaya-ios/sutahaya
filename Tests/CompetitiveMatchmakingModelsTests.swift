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
            "competitive": [
                "currentTier": "RATING_BATTLE",
                "ratingBattle": true,
                "displayRating": 1_640,
                "stats": [
                    "matchesPlayed": 10,
                    "totalWins": 4,
                    "maxWinStreak": 3,
                    "winRate": 0.4
                ],
                "season": [
                    "seasonId": "season-1",
                    "startsAtEpochMs": 500,
                    "endsAtEpochMs": 1_500
                ]
            ],
            "updatedAtEpochMs": 1_000
        ]))

        XCTAssertEqual(projection.state, .waitingPlayers)
        XCTAssertEqual(projection.competitiveSession, CompetitiveSession(
            uid: "player-1",
            matchId: "match-1",
            sessionId: "session-1",
            sessionEpoch: 3,
            assignmentTicket: "ticket-1"
        ))
        XCTAssertEqual(projection.competitive?.currentTier, .ratingBattle)
        XCTAssertEqual(projection.competitive?.displayRating, 1_640)
        XCTAssertEqual(projection.competitive?.stats.totalWins, 4)
        XCTAssertEqual(projection.competitive?.season.seasonId, "season-1")
    }

    func test_QUEUE中はMatchSessionを作らない() throws {
        let projection = try XCTUnwrap(CompetitiveMatchmakingProjection(databaseValue: [
            "uid": "player-1",
            "state": "QUEUED",
            "sessionId": "session-1",
            "sessionEpoch": 1,
            "protocolVersion": CompetitiveService.protocolVersion,
            "queuedAtEpochMs": 900,
            "nextCheckAfterMs": 5_000,
            "updatedAtEpochMs": 1_000
        ]))

        XCTAssertNil(projection.competitiveSession)
        XCTAssertEqual(projection.nextCheckAfterMS, 5_000)
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
            "assignmentTicket": "ticket-1",
            "nextCheckAfterMs": 5_000
        ]))

        XCTAssertEqual(ack.status, .accepted)
        XCTAssertEqual(ack.matchmakingState, .matchFound)
        XCTAssertEqual(ack.matchId, "match-1")
        XCTAssertEqual(ack.assignmentTicket, "ticket-1")
        XCTAssertEqual(ack.nextCheckAfterMs, 5_000)
    }
}
