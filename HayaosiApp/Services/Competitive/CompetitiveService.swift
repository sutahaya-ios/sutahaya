import Foundation
import Observation
import FirebaseDatabase
import FirebaseFunctions

enum CompetitiveServiceError: LocalizedError {
    case invalidPublicProjection
    case invalidMatchmakingProjection
    case invalidAck
    case noOpenQuestion
    case noActiveQueueSession

    var errorDescription: String? {
        switch self {
        case .invalidPublicProjection:
            "対戦状態を読み取れませんでした"
        case .invalidMatchmakingProjection:
            "マッチング状態を読み取れませんでした"
        case .invalidAck:
            "サーバー応答を読み取れませんでした"
        case .noOpenQuestion:
            "回答受付中の問題がありません"
        case .noActiveQueueSession:
            "キャンセルできる待機状態がありません"
        }
    }
}

/// Competitive Clientの通信境界。ClientはIntentだけを送り、結果はpublic projectionだけから受け取る。
@MainActor
@Observable
final class CompetitiveService {
    nonisolated static let protocolVersion = "competitive-v2-a2-1"
    nonisolated static let region = "asia-southeast1"

    private(set) var state: CompetitivePublicState?
    private(set) var listeningError: Error?

    private let session: CompetitiveSession
    private let database: DatabaseReference
    private let functions: Functions
    // Mutation is MainActor-only. `nonisolated(unsafe)` also lets synchronous deinit
    // detach Firebase's observer without crossing an actor boundary.
    @ObservationIgnored nonisolated(unsafe) private var publicReference: DatabaseReference?
    @ObservationIgnored nonisolated(unsafe) private var publicObserver: DatabaseHandle?

    init(
        session: CompetitiveSession,
        database: DatabaseReference = Database.database().reference(),
        functions: Functions = Functions.functions(region: CompetitiveService.region)
    ) {
        self.session = session
        self.database = database
        self.functions = functions
    }

    deinit {
        if let publicReference, let publicObserver {
            publicReference.removeObserver(withHandle: publicObserver)
        }
    }

    func startListening() {
        stopListening()
        let reference = database.child("competitiveV2/matches/\(session.matchId)/public")
        publicReference = reference
        publicObserver = reference.observe(.value) { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let state = CompetitivePublicState(databaseValue: snapshot.value) else {
                    self.listeningError = CompetitiveServiceError.invalidPublicProjection
                    return
                }
                self.state = state
                self.listeningError = nil
            }
        } withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                self?.listeningError = error
            }
        }
    }

    func stopListening() {
        if let publicReference, let publicObserver {
            publicReference.removeObserver(withHandle: publicObserver)
        }
        publicReference = nil
        publicObserver = nil
        state = nil
        listeningError = nil
    }

    func joinMatch(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(
            type: "joinMatch",
            eventId: eventId,
            payload: ["assignmentTicket": session.assignmentTicket]
        )
    }

    func ready(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(type: "ready", eventId: eventId)
    }

    func submitAnswer(
        answerId: String,
        eventId: String = UUID().uuidString
    ) async throws -> CompetitiveIntentAck {
        guard state?.phase == .questionOpen, let question = state?.currentQuestion else {
            throw CompetitiveServiceError.noOpenQuestion
        }
        return try await send(
            type: "submitAnswer",
            eventId: eventId,
            questionId: question.questionId,
            stateVersion: state?.stateVersion,
            payload: ["answerId": answerId]
        )
    }

    func leave(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(type: "leave", eventId: eventId)
    }

    private func send(
        type: String,
        eventId: String,
        questionId: String? = nil,
        stateVersion: Int? = nil,
        payload: [String: Any] = [:]
    ) async throws -> CompetitiveIntentAck {
        var envelope: [String: Any] = [
            "intentId": eventId,
            "type": type,
            "protocolVersion": Self.protocolVersion,
            "clientBuild": Self.clientBuild,
            "sessionId": session.sessionId,
            "sessionEpoch": session.sessionEpoch,
            "matchId": session.matchId,
            "lastSeenServerSequence": state?.serverSequence ?? 0,
            "payload": payload
        ]
        if let questionId { envelope["questionId"] = questionId }
        if let stateVersion { envelope["stateVersion"] = stateVersion }

        let response = try await functions.httpsCallable("competitiveIntent").call(envelope)
        guard let ack = CompetitiveIntentAck(value: response.data) else {
            throw CompetitiveServiceError.invalidAck
        }
        return ack
    }

    nonisolated static var clientBuild: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let safeBuild = build.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "-"
        }
        return "ios-\(String(safeBuild))"
    }
}

/// Queue参加からPhase A-2の`CompetitiveSession`受取までを担当する通信境界。
/// UIDはcallable payloadへ送らず、監視pathの指定にだけ使用する。Rulesが本人readを強制する。
@MainActor
@Observable
final class CompetitiveMatchmakingService {
    private(set) var state: CompetitiveMatchmakingProjection?
    private(set) var listeningError: Error?

    private let uid: String
    private let database: DatabaseReference
    private let functions: Functions
    @ObservationIgnored nonisolated(unsafe) private var projectionReference: DatabaseReference?
    @ObservationIgnored nonisolated(unsafe) private var projectionObserver: DatabaseHandle?

    init(
        uid: String,
        database: DatabaseReference = Database.database().reference(),
        functions: Functions = Functions.functions(region: CompetitiveService.region)
    ) {
        self.uid = uid
        self.database = database
        self.functions = functions
    }

    deinit {
        if let projectionReference, let projectionObserver {
            projectionReference.removeObserver(withHandle: projectionObserver)
        }
    }

    func observeMatchmakingState() {
        stopObservingMatchmakingState()
        let reference = database.child("competitiveV2/matchmaking/public/\(uid)")
        projectionReference = reference
        projectionObserver = reference.observe(.value) { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard snapshot.exists() else {
                    self.state = nil
                    self.listeningError = nil
                    return
                }
                guard let state = CompetitiveMatchmakingProjection(databaseValue: snapshot.value) else {
                    self.listeningError = CompetitiveServiceError.invalidMatchmakingProjection
                    return
                }
                self.state = state
                self.listeningError = nil
            }
        } withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                self?.listeningError = error
            }
        }
    }

    func stopObservingMatchmakingState() {
        if let projectionReference, let projectionObserver {
            projectionReference.removeObserver(withHandle: projectionObserver)
        }
        projectionReference = nil
        projectionObserver = nil
        state = nil
        listeningError = nil
    }

    func joinQueue(eventId: String = UUID().uuidString) async throws -> CompetitiveMatchmakingAck {
        try await send([
            "intentId": eventId,
            "type": "joinQueue",
            "protocolVersion": CompetitiveService.protocolVersion,
            "clientBuild": CompetitiveService.clientBuild,
            "payload": [:]
        ])
    }

    func cancelQueue(eventId: String = UUID().uuidString) async throws -> CompetitiveMatchmakingAck {
        guard let state, state.state == .queued else {
            throw CompetitiveServiceError.noActiveQueueSession
        }
        return try await send([
            "intentId": eventId,
            "type": "cancelQueue",
            "protocolVersion": CompetitiveService.protocolVersion,
            "clientBuild": CompetitiveService.clientBuild,
            "sessionId": state.sessionId,
            "sessionEpoch": state.sessionEpoch,
            "payload": [:]
        ])
    }

    private func send(_ envelope: [String: Any]) async throws -> CompetitiveMatchmakingAck {
        let response = try await functions.httpsCallable("competitiveMatchmaking").call(envelope)
        guard let ack = CompetitiveMatchmakingAck(value: response.data) else {
            throw CompetitiveServiceError.invalidAck
        }
        return ack
    }
}
