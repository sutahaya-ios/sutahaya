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

    func test_RankBadgeはServer進捗が50パーセントを超えた時だけUpperになる() {
        let cases: [(CompetitiveTier, Int, Double, CompetitiveClientDisplay.RankBadgeStage)] = [
            (.bronze, 1_099, 0.495, .base),
            (.bronze, 1_100, 0.5, .base),
            (.bronze, 1_101, 0.505, .upper),
            (.silver, 1_300, 0.5, .base),
            (.silver, 1_301, 0.505, .upper),
            (.gold, 1_500, 0.5, .base),
            (.gold, 1_501, 0.505, .upper),
            (.platinum, 1_700, 0.5, .base),
            (.platinum, 1_701, 0.505, .upper),
        ]

        for (tier, rating, progress, expected) in cases {
            let projection = profile(
                tier: tier,
                ratingBattle: false,
                displayRating: rating,
                currentRating: rating,
                progressFraction: progress
            )
            XCTAssertEqual(CompetitiveClientDisplay.rankBadgeStage(for: projection), expected)
        }
    }

    func test_Tier昇格とRatingBattleはBaseBadgeから始まる() {
        let silver = profile(
            tier: .silver,
            ratingBattle: false,
            displayRating: 1_200,
            currentRating: 1_200,
            progressFraction: 0
        )
        let ratingBattle = profile(
            tier: .ratingBattle,
            ratingBattle: true,
            displayRating: 2_500,
            currentRating: 2_500,
            progressFraction: 1
        )

        XCTAssertEqual(CompetitiveClientDisplay.rankBadgeStage(for: silver), .base)
        XCTAssertEqual(CompetitiveClientDisplay.rankBadgeStage(for: ratingBattle), .base)
        XCTAssertEqual(
            CompetitiveClientDisplay.rankBadgeAssetName(tier: .silver, stage: .base),
            "rank_silver_base"
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.rankBadgeAssetName(tier: .ratingBattle, stage: .base),
            "rank_rating_base"
        )
    }

    func test_Badge進化Animationは同一Tierで上方向に50パーセントを跨ぐ時だけ() {
        let bronze1090 = profile(
            tier: .bronze,
            ratingBattle: false,
            displayRating: 1_090,
            currentRating: 1_090,
            progressFraction: 0.45
        )
        let bronze1110 = profile(
            tier: .bronze,
            ratingBattle: false,
            displayRating: 1_110,
            currentRating: 1_110,
            progressFraction: 0.55
        )
        let bronze1120 = profile(
            tier: .bronze,
            ratingBattle: false,
            displayRating: 1_120,
            currentRating: 1_120,
            progressFraction: 0.6
        )
        let silver1200 = profile(
            tier: .silver,
            ratingBattle: false,
            displayRating: 1_200,
            currentRating: 1_200,
            progressFraction: 0
        )

        XCTAssertTrue(
            CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: bronze1090,
                to: bronze1110
            )
        )
        XCTAssertFalse(
            CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: bronze1110,
                to: bronze1120
            )
        )
        XCTAssertFalse(
            CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: bronze1120,
                to: bronze1090
            )
        )
        XCTAssertFalse(
            CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: bronze1120,
                to: silver1200
            )
        )
        XCTAssertFalse(
            CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: nil,
                to: bronze1110
            ),
            "App再起動時は現在のUpperを即表示し、進化Animationを再生しない"
        )
    }

    func test_Rule表示は現在TierのNPC補充設定に一致する() {
        XCTAssertEqual(
            CompetitiveClientDisplay.competitiveRuleSummary(
                for: profile(tier: .bronze, ratingBattle: false, displayRating: 1_000)
            ),
            "20問 / 4人対戦 / Bronzeは5秒でNPC補充"
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.competitiveRuleSummary(
                for: profile(tier: .silver, ratingBattle: false, displayRating: 1_200)
            ),
            "20問 / 4人対戦 / Silverは10秒でNPC補充"
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.competitiveRuleSummary(
                for: profile(tier: .gold, ratingBattle: false, displayRating: 1_400)
            ),
            "20問 / 4人対戦 / Gold以上はNPC補充なし"
        )
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

    func test_QUESTION_OPENはHumanとNPCのansweredを共通表示する() {
        let human = participant(uid: "human", kind: .human, answered: true)
        let npc = participant(uid: "npc", kind: .npc, answered: true)
        let unansweredNPC = participant(uid: "npc-2", kind: .npc, answered: false)

        XCTAssertTrue(CompetitiveClientDisplay.showsAnswered(human, phase: .questionOpen))
        XCTAssertTrue(CompetitiveClientDisplay.showsAnswered(npc, phase: .questionOpen))
        XCTAssertFalse(
            CompetitiveClientDisplay.showsAnswered(unansweredNPC, phase: .questionOpen)
        )
        XCTAssertFalse(CompetitiveClientDisplay.showsAnswered(npc, phase: .questionResult))
    }

    func test_正誤と得点差分はQUESTION_RESULT後だけ表示する() {
        XCTAssertEqual(CompetitiveClientDisplay.questionCount, 20)

        let correct = participant(uid: "correct", kind: .human, answered: true)
        let wrongNPC = participant(uid: "wrong-npc", kind: .npc, answered: true)
        let unanswered = participant(uid: "unanswered", kind: .human, answered: false)
        let result = CompetitiveQuestionResult(
            questionId: "q-1",
            questionIndex: 0,
            closeReason: "ALL_ANSWERED",
            answerOrder: [correct.uid, wrongNPC.uid],
            correctUIDs: [correct.uid],
            wrongUIDs: [wrongNPC.uid],
            unansweredUIDs: [unanswered.uid],
            scoreDeltas: [correct.uid: 20, wrongNPC.uid: -10, unanswered.uid: 0],
            cumulativeScores: [correct.uid: 20, wrongNPC.uid: -10, unanswered.uid: 0],
            correctAnswerId: "a-1",
            closedAtEpochMS: 1_000
        )

        XCTAssertEqual(
            CompetitiveClientDisplay.answerState(
                for: correct,
                phase: .questionOpen,
                result: result
            ),
            .answered,
            "回答受付中はServerに結果があっても正誤を公開しない"
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.answerState(
                for: correct,
                phase: .questionResult,
                result: result
            ),
            .correct
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.answerState(
                for: wrongNPC,
                phase: .questionResult,
                result: result
            ),
            .wrong
        )
        XCTAssertEqual(
            CompetitiveClientDisplay.answerState(
                for: unanswered,
                phase: .questionResult,
                result: result
            ),
            .none
        )
        XCTAssertEqual(BattleScoreBoard.DisplayBadge.scoreDelta(20).text, "+20")
        XCTAssertEqual(BattleScoreBoard.DisplayBadge.scoreDelta(-10).text, "-10")
        XCTAssertEqual(BattleScoreBoard.DisplayBadge.scoreDelta(0).text, "±0")
    }

    func test_ServerAction時刻をdeadlineより優先してReconcileする() throws {
        let npcDue = try XCTUnwrap(publicState(nextServerActionAtEpochMS: 3_100))
        let deadlineOnly = try XCTUnwrap(publicState())

        XCTAssertEqual(
            CompetitiveReconcileSchedule.dueEpochMS(for: npcDue, actorUID: "player-1"),
            3_100
        )
        XCTAssertEqual(
            CompetitiveReconcileSchedule.dueEpochMS(for: npcDue, actorUID: "other-player"),
            5_100
        )
        XCTAssertEqual(
            CompetitiveReconcileSchedule.dueEpochMS(for: deadlineOnly, actorUID: "player-1"),
            5_100
        )
        XCTAssertNil(npcDue.currentQuestion?.correctAnswerId)
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

    func test_ExplicitForfeitはAcceptedとAcceptedDuplicateだけ成功扱いにする() throws {
        let accepted = try XCTUnwrap(intentAck(status: "ACCEPTED"))
        let duplicate = try XCTUnwrap(
            intentAck(status: "DUPLICATE", originalStatus: "ACCEPTED")
        )
        let rejected = try XCTUnwrap(intentAck(status: "REJECTED"))

        XCTAssertTrue(CompetitiveExplicitForfeitPolicy.wasAccepted(accepted))
        XCTAssertTrue(CompetitiveExplicitForfeitPolicy.wasAccepted(duplicate))
        XCTAssertFalse(CompetitiveExplicitForfeitPolicy.wasAccepted(rejected))
    }

    func test_ExplicitForfeit済みSessionは再起動後も復元対象外() throws {
        let suiteName = "CompetitiveClientPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompetitiveExplicitForfeitStore(defaults: defaults)
        let activeSession = session()
        let marker = CompetitiveExplicitForfeitMarker(session: activeSession)

        store.save(marker)
        let restoredMarker = try XCTUnwrap(
            CompetitiveExplicitForfeitStore(defaults: defaults).load()
        )

        XCTAssertEqual(restoredMarker, marker)
        XCTAssertTrue(
            CompetitiveExplicitForfeitPolicy.suppresses(
                session: activeSession,
                marker: restoredMarker
            )
        )
        XCTAssertEqual(
            CompetitiveClientScreen.resolve(matchmakingState: .notQueued, hasActiveMatch: false),
            .home
        )
    }

    func test_ExplicitForfeit済みRoomAはRoomBとReconnectを妨げない() {
        let roomA = session()
        let marker = CompetitiveExplicitForfeitMarker(session: roomA)
        let roomB = CompetitiveSession(
            uid: roomA.uid,
            matchId: "match-c",
            sessionId: "session-c",
            sessionEpoch: roomA.sessionEpoch + 1,
            assignmentTicket: "ticket-c"
        )

        XCTAssertTrue(
            CompetitiveExplicitForfeitPolicy.suppresses(session: roomA, marker: marker)
        )
        XCTAssertFalse(
            CompetitiveExplicitForfeitPolicy.suppresses(session: roomB, marker: marker)
        )
    }

    func test_SettlementReleaseまたは新SessionでForfeitMarkerを解除する() throws {
        let marker = CompetitiveExplicitForfeitMarker(session: session())
        let waiting = try XCTUnwrap(matchmakingProjection())
        let released = try XCTUnwrap(matchmakingProjection(state: "NOT_QUEUED"))
        let nextSession = try XCTUnwrap(
            matchmakingProjection(
                sessionId: "session-c",
                sessionEpoch: 3,
                matchId: "match-c"
            )
        )

        XCTAssertFalse(
            CompetitiveExplicitForfeitPolicy.isReleased(marker: marker, projection: waiting)
        )
        XCTAssertTrue(
            CompetitiveExplicitForfeitPolicy.isReleased(marker: marker, projection: released)
        )
        XCTAssertTrue(
            CompetitiveExplicitForfeitPolicy.isReleased(marker: marker, projection: nextSession)
        )
    }

    func test_ExplicitForfeitCooldownはServer時刻補正込みで秒数を表示する() throws {
        let projection = try XCTUnwrap(
            matchmakingProjection(
                state: "NOT_QUEUED",
                matchId: nil,
                forfeitCompletedAtEpochMS: 1_000,
                cooldownEndsAtEpochMS: 6_000
            )
        )
        XCTAssertEqual(projection.forfeitCompletedAtEpochMS, 1_000)
        XCTAssertEqual(projection.cooldownEndsAtEpochMS, 6_000)
        XCTAssertEqual(
            CompetitiveForfeitCooldownPolicy.remainingSeconds(
                cooldownEndsAtEpochMS: projection.cooldownEndsAtEpochMS,
                clientNowEpochMS: 2_100,
                serverTimeOffsetMS: 900
            ),
            3
        )
        XCTAssertEqual(
            CompetitiveForfeitCooldownPolicy.remainingSeconds(
                cooldownEndsAtEpochMS: projection.cooldownEndsAtEpochMS,
                clientNowEpochMS: 5_100,
                serverTimeOffsetMS: 900
            ),
            0
        )
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
        phase: CompetitivePhase? = nil,
        nextServerActionAtEpochMS: Double? = nil
    ) -> CompetitivePublicState? {
        let resolvedPhase = phase ?? (settled ? .settled : .questionOpen)
        var question: [String: Any] = [
            "questionId": "q-1",
            "questionIndex": 0,
            "prompt": "apple",
            "choices": [["answerId": "a-1", "text": "りんご"]],
            "openedAtEpochMs": 100,
            "deadlineEpochMs": 5_100
        ]
        if let nextServerActionAtEpochMS {
            question["nextServerActionAtEpochMs"] = nextServerActionAtEpochMS
        }
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
            "currentQuestion": question
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

    private func participant(
        uid: String,
        kind: CompetitiveParticipant.Kind,
        answered: Bool
    ) -> CompetitiveParticipant {
        CompetitiveParticipant(
            uid: uid,
            slot: 0,
            kind: kind,
            displayName: uid,
            joined: true,
            ready: true,
            active: true,
            forfeited: false,
            status: .connected,
            disconnectedAtEpochMS: nil,
            reconnectDeadlineEpochMS: nil,
            answered: answered,
            score: 0
        )
    }

    private func intentAck(
        status: String,
        originalStatus: String? = nil
    ) -> CompetitiveIntentAck? {
        var value: [String: Any] = [
            "intentId": UUID().uuidString,
            "status": status,
            "retryable": false,
        ]
        if let originalStatus { value["originalStatus"] = originalStatus }
        return CompetitiveIntentAck(value: value)
    }

    private func matchmakingProjection(
        state: String = "WAITING_PLAYERS",
        sessionId: String = "session-b",
        sessionEpoch: Int = 2,
        matchId: String? = "match-b",
        forfeitCompletedAtEpochMS: Double? = nil,
        cooldownEndsAtEpochMS: Double? = nil
    ) -> CompetitiveMatchmakingProjection? {
        var value: [String: Any] = [
            "uid": "player-1",
            "state": state,
            "sessionId": sessionId,
            "sessionEpoch": sessionEpoch,
            "protocolVersion": CompetitiveService.protocolVersion,
            "updatedAtEpochMs": 1_000,
        ]
        if let matchId {
            value["matchId"] = matchId
            value["assignmentTicket"] = "ticket"
        }
        if let forfeitCompletedAtEpochMS {
            value["forfeitCompletedAtEpochMs"] = forfeitCompletedAtEpochMS
        }
        if let cooldownEndsAtEpochMS {
            value["cooldownEndsAtEpochMs"] = cooldownEndsAtEpochMS
        }
        return CompetitiveMatchmakingProjection(databaseValue: value)
    }
}
