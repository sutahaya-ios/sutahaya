import Foundation

struct CompetitiveSessionKey: Codable, Equatable, Hashable, Sendable {
    let matchId: String
    let sessionId: String
    let sessionEpoch: Int

    init(session: CompetitiveSession) {
        matchId = session.matchId
        sessionId = session.sessionId
        sessionEpoch = session.sessionEpoch
    }
}

struct CompetitiveExplicitForfeitMarker: Codable, Equatable, Sendable {
    let uid: String
    let sessionKey: CompetitiveSessionKey

    init(session: CompetitiveSession) {
        uid = session.uid
        sessionKey = CompetitiveSessionKey(session: session)
    }
}

struct CompetitiveExplicitForfeitStore {
    private static let storageKey = "competitive.explicitForfeitSession"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CompetitiveExplicitForfeitMarker? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(CompetitiveExplicitForfeitMarker.self, from: data)
    }

    func save(_ marker: CompetitiveExplicitForfeitMarker) {
        guard let data = try? JSONEncoder().encode(marker) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

enum CompetitiveExplicitForfeitPolicy {
    static func wasAccepted(_ acknowledgement: CompetitiveIntentAck) -> Bool {
        acknowledgement.status == .accepted
            || (acknowledgement.status == .duplicate
                && acknowledgement.originalStatus == .accepted)
    }

    static func suppresses(
        session: CompetitiveSession,
        marker: CompetitiveExplicitForfeitMarker?
    ) -> Bool {
        guard let marker else { return false }
        return marker.uid == session.uid
            && marker.sessionKey == CompetitiveSessionKey(session: session)
    }

    static func isReleased(
        marker: CompetitiveExplicitForfeitMarker,
        projection: CompetitiveMatchmakingProjection?
    ) -> Bool {
        guard let projection, projection.uid == marker.uid else { return false }
        return projection.state == .notQueued
            || projection.sessionId != marker.sessionKey.sessionId
            || projection.sessionEpoch != marker.sessionKey.sessionEpoch
    }
}

enum CompetitiveForfeitCooldownPolicy {
    static func remainingSeconds(
        cooldownEndsAtEpochMS: Double?,
        clientNowEpochMS: Double,
        serverTimeOffsetMS: Double
    ) -> Int {
        guard let cooldownEndsAtEpochMS else { return 0 }
        let serverNowEpochMS = clientNowEpochMS + serverTimeOffsetMS
        return max(0, Int(ceil((cooldownEndsAtEpochMS - serverNowEpochMS) / 1_000)))
    }
}

struct CompetitiveDisplayedQuestionContext: Equatable, Sendable {
    let sessionKey: CompetitiveSessionKey
    let questionId: String
    let questionIndex: Int
    let stateVersion: Int

    func matches(session: CompetitiveSession, state: CompetitivePublicState?) -> Bool {
        guard sessionKey == CompetitiveSessionKey(session: session),
              let state,
              state.matchId == session.matchId,
              state.phase == .questionOpen,
              let question = state.currentQuestion else { return false }
        return question.questionId == questionId
            && question.questionIndex == questionIndex
            && state.stateVersion == stateVersion
    }
}

enum CompetitiveProjectionPolicy {
    static func shouldAccept(
        _ candidate: CompetitivePublicState,
        for session: CompetitiveSession,
        after current: CompetitivePublicState?
    ) -> Bool {
        guard candidate.matchId == session.matchId,
              candidate.protocolVersion == CompetitiveService.protocolVersion else { return false }
        guard let current else { return true }
        return candidate.serverSequence >= current.serverSequence
    }
}

enum CompetitiveReconcileSchedule {
    static func dueEpochMS(
        for state: CompetitivePublicState,
        actorUID: String
    ) -> Double? {
        switch state.phase {
        case .countdown:
            return state.countdownEndsAtEpochMS
        case .questionOpen:
            guard let question = state.currentQuestion else { return nil }
            let leaderUID = state.participants
                .filter { $0.kind == .human && $0.active && $0.status == .connected }
                .min { $0.slot < $1.slot }?
                .uid
            guard leaderUID == actorUID else { return question.deadlineEpochMS }
            return min(
                question.nextServerActionAtEpochMS ?? question.deadlineEpochMS,
                question.deadlineEpochMS
            )
        case .questionResult:
            return state.resultEndsAtEpochMS
        case .nextQuestion:
            return 0
        case .created, .waitingPlayers, .matchFinished, .settlementPending, .settled:
            return nil
        }
    }
}

enum CompetitiveSettlementRecoveryAction: Equatable {
    case none
    case refreshAndReconcile
    case complete
}

enum CompetitiveSettlementRecoveryPolicy {
    static let delayedThreshold = 8
    static let retryDelayMilliseconds = 1_000

    static func action(
        for state: CompetitivePublicState?,
        sessionKey: CompetitiveSessionKey
    ) -> CompetitiveSettlementRecoveryAction {
        guard let state, state.matchId == sessionKey.matchId else { return .none }
        switch state.phase {
        case .matchFinished, .settlementPending:
            return .refreshAndReconcile
        case .settled:
            return .complete
        default:
            return .none
        }
    }

    static func isDelayed(attempt: Int) -> Bool {
        attempt >= delayedThreshold
    }

    static func shouldCompleteResult(
        action: CompetitiveSettlementRecoveryAction,
        completedSessionKey: CompetitiveSessionKey?,
        expectedSessionKey: CompetitiveSessionKey
    ) -> Bool {
        action == .complete && completedSessionKey != expectedSessionKey
    }
}

enum CompetitiveClientDisplay {
    static let questionCount = 20

    static func tierName(_ tier: CompetitiveTier) -> String {
        switch tier {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .ratingBattle: "Rating Battle"
        }
    }

    static func ratingText(for profile: CompetitiveProfileProjection?) -> String? {
        guard let profile,
              let rating = profile.currentRating ?? profile.displayRating else { return nil }
        return "\(rating) pt"
    }

    static func rankProgress(for profile: CompetitiveProfileProjection?) -> Double? {
        guard let profile,
              !profile.ratingBattle,
              profile.currentTier != .ratingBattle,
              let progress = profile.progressFraction else { return nil }
        return min(1, max(0, progress))
    }

    static func pointsToNextTierText(for profile: CompetitiveProfileProjection?) -> String? {
        guard let profile,
              !profile.ratingBattle,
              profile.currentTier != .ratingBattle,
              let points = profile.pointsToNextTier else { return nil }
        return "次のランクまで \(max(0, points))"
    }

    static func winRateText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func scoreDeltaText(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta == 0 { return "±0" }
        return "\(delta)"
    }

    static func showsAnswered(
        _ participant: CompetitiveParticipant,
        phase: CompetitivePhase
    ) -> Bool {
        phase == .questionOpen && participant.answered
    }

    static func canCancelQueue(_ state: CompetitiveMatchmakingState?) -> Bool {
        state == .queued
    }

    static func userMessage(for error: Error) -> String {
        if let serviceError = error as? CompetitiveServiceError {
            return serviceError.localizedDescription
        }
        return "通信状態を確認して、もう一度お試しください"
    }

    static func rejectionMessage(_ code: String?) -> String {
        switch code {
        case "STALE_SESSION_EPOCH", "SESSION_NOT_ACTIVE":
            "対戦情報が更新されました。現在の状態を読み直してください"
        case "MATCH_ALREADY_ASSIGNED", "ACTIVE_MATCH_EXISTS":
            "すでに進行中の対戦があります"
        case "FORFEIT_COOLDOWN_ACTIVE":
            "棄権後の再参加待機中です"
        case "QUESTION_NOT_OPEN", "STALE_QUESTION", "STALE_STATE_VERSION":
            "この問題の回答受付は終了しました"
        case "ALREADY_ANSWERED":
            "この問題には回答済みです"
        case "PLAYER_FORFEITED", "MATCH_FINISHED":
            "この対戦は終了しています"
        default:
            "サーバーで操作を受け付けられませんでした"
        }
    }
}

enum CompetitiveClientScreen: Equatable {
    case home
    case matchmaking
    case match

    static func resolve(
        matchmakingState: CompetitiveMatchmakingState?,
        hasActiveMatch: Bool
    ) -> CompetitiveClientScreen {
        if hasActiveMatch { return .match }
        switch matchmakingState {
        case .queued, .matchFound, .waitingPlayers:
            return .matchmaking
        case .notQueued, nil:
            return .home
        }
    }
}
