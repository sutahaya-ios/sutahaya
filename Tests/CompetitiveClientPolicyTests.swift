import XCTest
@testable import HayaosiApp

final class CompetitiveClientPolicyTests: XCTestCase {
    func test_BronzeからPlatinumはServer投影のRatingと進捗を表示する() {
        let cases: [(CompetitiveTier, Int, Double, Int)] = [
            (.bronze, 1_128, 0.64, 72),
            (.silver, 1_250, 0.25, 150),
            (.gold, 1_500, 0.5, 100),
            (.platinum, 1_700, 0.5, 100),
            (.platinum, 1_850, 1, 0),
        ]
        for (tier, rating, progress, remaining) in cases {
            let profile = profile(
                tier: tier,
                ratingBattle: false,
                displayRating: nil,
                currentRating: rating,
                progressFraction: progress,
                pointsToNextTier: remaining
            )
            XCTAssertEqual(CompetitiveClientDisplay.ratingText(for: profile), "\(rating) pt")
            XCTAssertEqual(CompetitiveClientDisplay.rankProgress(for: profile), progress)
            XCTAssertEqual(
                CompetitiveClientDisplay.pointsToNextTierText(for: profile),
                "次のランクまで \(remaining)"
            )
        }
        let profile = profile(tier: .bronze, ratingBattle: false, displayRating: nil)
        XCTAssertEqual(CompetitiveClientDisplay.tierName(profile.currentTier), "Bronze")
        XCTAssertNil(CompetitiveClientDisplay.ratingText(for: profile))
        XCTAssertEqual(CompetitiveClientDisplay.winRateText(profile.stats.winRate), "50%")
    }

    func test_RatingBattleはRatingだけ表示してMeterを出さない() {
        let profile = profile(
            tier: .ratingBattle,
            ratingBattle: true,
            displayRating: 1_842,
            currentRating: 1_842
        )
        XCTAssertEqual(CompetitiveClientDisplay.ratingText(for: profile), "1842 pt")
        XCTAssertNil(CompetitiveClientDisplay.rankProgress(for: profile))
        XCTAssertNil(CompetitiveClientDisplay.pointsToNextTierText(for: profile))
    }

    func test_MATCH_FOUND以降はQueueキャンセル不可() {
        XCTAssertTrue(CompetitiveClientDisplay.canCancelQueue(.queued))
        XCTAssertFalse(CompetitiveClientDisplay.canCancelQueue(.matchFound))
        XCTAssertFalse(CompetitiveClientDisplay.canCancelQueue(.waitingPlayers))
    }

    func test_得点差分を符号付きで表示する() {
        XCTAssertEqual(CompetitiveClientDisplay.scoreDeltaText(20), "+20")
        XCTAssertEqual(CompetitiveClientDisplay.scoreDeltaText(-10), "-10")
        XCTAssertEqual(CompetitiveClientDisplay.scoreDeltaText(0), "±0")
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

    func test_Match終了からSettlement完了までResult回復を継続する() throws {
        let key = CompetitiveSessionKey(session: session())
        let finished = try XCTUnwrap(publicState(phase: .matchFinished))
        let pending = try XCTUnwrap(publicState(phase: .settlementPending))
        let settled = try XCTUnwrap(publicState(phase: .settled))

        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(for: finished, sessionKey: key),
            .refreshAndReconcile
        )
        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(for: pending, sessionKey: key),
            .refreshAndReconcile
        )
        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(for: settled, sessionKey: key),
            .complete
        )
    }

    func test_SettledListenerを取りこぼしても再読込値を採用できる() throws {
        let activeSession = session()
        let pending = try XCTUnwrap(publicState(serverSequence: 20, phase: .settlementPending))
        let reread = try XCTUnwrap(publicState(serverSequence: 21, phase: .settled))

        XCTAssertTrue(
            CompetitiveProjectionPolicy.shouldAccept(reread, for: activeSession, after: pending)
        )
        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(
                for: reread,
                sessionKey: CompetitiveSessionKey(session: activeSession)
            ),
            .complete
        )
    }

    func test_SettlementTimeout後もServer再取得を継続する() throws {
        let key = CompetitiveSessionKey(session: session())
        let pending = try XCTUnwrap(publicState(phase: .settlementPending))

        XCTAssertFalse(
            CompetitiveSettlementRecoveryPolicy.isDelayed(
                attempt: CompetitiveSettlementRecoveryPolicy.delayedThreshold - 1
            )
        )
        XCTAssertTrue(
            CompetitiveSettlementRecoveryPolicy.isDelayed(
                attempt: CompetitiveSettlementRecoveryPolicy.delayedThreshold
            )
        )
        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(for: pending, sessionKey: key),
            .refreshAndReconcile
        )
    }

    func test_DuplicateSettledはResult完了を二重実行しない() {
        let key = CompetitiveSessionKey(session: session())
        XCTAssertTrue(
            CompetitiveSettlementRecoveryPolicy.shouldCompleteResult(
                action: .complete,
                completedSessionKey: nil,
                expectedSessionKey: key
            )
        )
        XCTAssertFalse(
            CompetitiveSettlementRecoveryPolicy.shouldCompleteResult(
                action: .complete,
                completedSessionKey: key,
                expectedSessionKey: key
            )
        )
    }

    func test_RoomAのSettlementはRoomBのResultへ影響しない() throws {
        let roomB = CompetitiveSessionKey(session: session())
        let roomAState = try XCTUnwrap(publicState(matchId: "match-a", phase: .settled))

        XCTAssertEqual(
            CompetitiveSettlementRecoveryPolicy.action(for: roomAState, sessionKey: roomB),
            .none
        )
    }

    func test_PresenceはSessionFenceを保ったOfflineTombstoneを生成する() {
        let session = session()
        let online = CompetitiveService.presencePayload(
            session: session,
            connected: true,
            timestamp: 123
        )
        XCTAssertEqual(online["connected"] as? Bool, true)
        XCTAssertEqual(online["matchId"] as? String, session.matchId)
        XCTAssertEqual(online["sessionId"] as? String, session.sessionId)
        XCTAssertEqual(online["sessionEpoch"] as? Int, session.sessionEpoch)
        XCTAssertEqual(online["updatedAtEpochMs"] as? Int, 123)
        XCTAssertNil(online["disconnectedAtEpochMs"])

        let offline = CompetitiveService.presencePayload(
            session: session,
            connected: false,
            timestamp: 456
        )
        XCTAssertEqual(offline["connected"] as? Bool, false)
        XCTAssertEqual(offline["matchId"] as? String, session.matchId)
        XCTAssertEqual(offline["sessionId"] as? String, session.sessionId)
        XCTAssertEqual(offline["sessionEpoch"] as? Int, session.sessionEpoch)
        XCTAssertEqual(offline["updatedAtEpochMs"] as? Int, 456)
        XCTAssertEqual(offline["disconnectedAtEpochMs"] as? Int, 456)
    }

    private func profile(
        tier: CompetitiveTier,
        ratingBattle: Bool,
        displayRating: Int?,
        currentRating: Int? = nil,
        progressFraction: Double? = nil,
        pointsToNextTier: Int? = nil
    ) -> CompetitiveProfileProjection {
        CompetitiveProfileProjection(
            currentTier: tier,
            ratingBattle: ratingBattle,
            displayRating: displayRating,
            currentRating: currentRating,
            progressFraction: progressFraction,
            pointsToNextTier: pointsToNextTier,
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
        settled: Bool = false,
        phase: CompetitivePhase? = nil
    ) -> CompetitivePublicState? {
        let resolvedPhase = phase ?? (settled ? .settled : .questionOpen)
        var value: [String: Any] = [
            "matchId": matchId,
            "protocolVersion": CompetitiveService.protocolVersion,
            "configVersion": "config-1",
            "phase": resolvedPhase.rawValue,
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
        if resolvedPhase == .settled {
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
