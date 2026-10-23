import Foundation

struct CompetitiveSessionKey: Equatable, Hashable, Sendable {
    let matchId: String
    let sessionId: String
    let sessionEpoch: Int

    init(session: CompetitiveSession) {
        matchId = session.matchId
        sessionId = session.sessionId
        sessionEpoch = session.sessionEpoch
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
