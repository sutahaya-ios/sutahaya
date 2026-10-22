import XCTest
@testable import HayaosiApp

final class CompetitiveClientPolicyTests: XCTestCase {
    func test_BronzeはRating数値を表示しない() {
        let profile = profile(tier: .bronze, ratingBattle: false, displayRating: nil)
        XCTAssertEqual(CompetitiveClientDisplay.tierName(profile.currentTier), "Bronze")
        XCTAssertNil(CompetitiveClientDisplay.ratingText(for: profile))
        XCTAssertEqual(CompetitiveClientDisplay.winRateText(profile.stats.winRate), "50%")
    }

    func test_RatingBattleだけServerのdisplayRatingを表示する() {
        let profile = profile(tier: .ratingBattle, ratingBattle: true, displayRating: 1_842)
        XCTAssertEqual(CompetitiveClientDisplay.ratingText(for: profile), "Rating 1842")
    }

    func test_MATCH_FOUND以降はQueueキャンセル不可() {
        XCTAssertTrue(CompetitiveClientDisplay.canCancelQueue(.queued))
        XCTAssertFalse(CompetitiveClientDisplay.canCancelQueue(.matchFound))
        XCTAssertFalse(CompetitiveClientDisplay.canCancelQueue(.waitingPlayers))
    }

    func test_ActiveMatchはQueue表示より優先される() {
        XCTAssertEqual(
            CompetitiveClientScreen.resolve(matchmakingState: .queued, hasActiveMatch: true),
            .match
        )
        XCTAssertEqual(
            CompetitiveClientScreen.resolve(matchmakingState: .queued, hasActiveMatch: false),
            .matchmaking
        )
    }

    func test_表示した問題contextだけ回答できる() throws {
        let session = session()
        let state = try XCTUnwrap(publicState())
        let context = CompetitiveDisplayedQuestionContext(
            sessionKey: CompetitiveSessionKey(session: session),
            questionId: "q-1",
            questionIndex: 0,
            stateVersion: 4
        )
        XCTAssertTrue(context.matches(session: session, state: state))
        let stale = CompetitiveDisplayedQuestionContext(
            sessionKey: CompetitiveSessionKey(session: session),
            questionId: "q-old",
            questionIndex: 0,
            stateVersion: 3
        )
        XCTAssertFalse(stale.matches(session: session, state: state))
    }

    func test_RoomAのprojectionと古いsequenceを拒否する() throws {
        let session = session()
        let current = try XCTUnwrap(publicState(serverSequence: 10))
        let staleSequence = try XCTUnwrap(publicState(serverSequence: 9))
        let otherMatch = try XCTUnwrap(publicState(matchId: "match-a", serverSequence: 11))
        XCTAssertFalse(CompetitiveProjectionPolicy.shouldAccept(staleSequence, for: session, after: current))
        XCTAssertFalse(CompetitiveProjectionPolicy.shouldAccept(otherMatch, for: session, after: current))
        XCTAssertTrue(CompetitiveProjectionPolicy.shouldAccept(current, for: session, after: nil))
    }

    func test_PublicSettlementから昇格とRating差分を復元する() throws {
        let state = try XCTUnwrap(publicState(settled: true))
        let result = try XCTUnwrap(state.settlement?.playerResults["player-1"])
        XCTAssertEqual(result.previousTier, .platinum)
        XCTAssertEqual(result.currentTier, .ratingBattle)
        XCTAssertEqual(result.displayRating, 1_818)
        XCTAssertEqual(result.ratingDelta, 18)
    }

    private func profile(
        tier: CompetitiveTier,
        ratingBattle: Bool,
        displayRating: Int?
    ) -> CompetitiveProfileProjection {
        CompetitiveProfileProjection(
            currentTier: tier,
            ratingBattle: ratingBattle,
            displayRating: displayRating,
            stats: CompetitiveStatsProjection(totalWins: 5, maxWinStreak: 3, winRate: 0.5),
            season: CompetitiveSeasonProjection(
                seasonId: "season-1",
                startsAtEpochMS: 0,
                endsAtEpochMS: 1_000
            )
        )
    }

    private func session() -> CompetitiveSession {
        CompetitiveSession(
            uid: "player-1",
            matchId: "match-b",
            sessionId: "session-b",
            sessionEpoch: 2,
            assignmentTicket: "ticket-b"
        )
    }

    private func publicState(
        matchId: String = "match-b",
        serverSequence: Int = 10,
        settled: Bool = false
    ) -> CompetitivePublicState? {
        var value: [String: Any] = [
            "matchId": matchId,
            "protocolVersion": CompetitiveService.protocolVersion,
            "configVersion": "config-1",
            "phase": settled ? "SETTLED" : "QUESTION_OPEN",
            "stateVersion": 4,
            "serverSequence": serverSequence,
            "currentQuestionIndex": 0,
            "participants": [
                "player-1": [
                    "slot": 0,
                    "kind": "HUMAN",
                    "displayName": "Player 1",
                    "joined": true,
                    "ready": true,
                    "active": true,
                    "forfeited": false,
                    "status": "CONNECTED",
                    "answered": false,
                    "score": 0
                ]
            ],
            "currentQuestion": [
                "questionId": "q-1",
                "questionIndex": 0,
                "prompt": "apple",
                "choices": [["answerId": "a-1", "text": "りんご"]],
                "openedAtEpochMs": 100,
                "deadlineEpochMs": 5_100
            ]
        ]
        if settled {
            value["settlement"] = [
                "status": "SETTLED",
                "settlementId": "match-b:settlement",
                "playerResults": [
                    "player-1": [
                        "rank": 1,
                        "forfeited": false,
                        "previousTier": "PLATINUM",
                        "currentTier": "RATING_BATTLE",
                        "ratingBattle": true,
                        "displayRating": 1_818,
                        "ratingDelta": 18
                    ]
                ]
            ]
        }
        return CompetitivePublicState(databaseValue: value)
    }
}
