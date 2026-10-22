import Foundation
import Observation
import UIKit
import FirebaseDatabase
import FirebaseFunctions

enum CompetitiveServiceError: LocalizedError {
    case invalidPublicProjection
    case invalidMatchmakingProjection
    case invalidAck
    case noOpenQuestion
    case noActiveQueueSession
    case staleDisplayedQuestion

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
        case .staleDisplayedQuestion:
            "表示中の問題が更新されました"
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
    @ObservationIgnored nonisolated(unsafe) private var presenceReference: DatabaseReference?
    @ObservationIgnored nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

    init(
        session: CompetitiveSession,
        database: DatabaseReference = Database.database().reference(),
        functions: Functions = Functions.functions(region: CompetitiveService.region)
    ) {
        self.session = session
        self.database = database
        self.functions = functions
        observeAppLifecycle()
    }

    deinit {
        if let publicReference, let publicObserver {
            publicReference.removeObserver(withHandle: publicObserver)
        }
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
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
                guard CompetitiveProjectionPolicy.shouldAccept(
                    state,
                    for: self.session,
                    after: self.state
                ) else { return }
                self.state = state
                self.listeningError = nil
            }
        } withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                self?.listeningError = error
            }
        }
        Task { [weak self] in
            do {
                try await self?.registerConnectedPresence()
            } catch {
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

    func displayedQuestionContext() -> CompetitiveDisplayedQuestionContext? {
        guard let state,
              state.phase == .questionOpen,
              let question = state.currentQuestion else { return nil }
        return CompetitiveDisplayedQuestionContext(
            sessionKey: CompetitiveSessionKey(session: session),
            questionId: question.questionId,
            questionIndex: question.questionIndex,
            stateVersion: state.stateVersion
        )
    }

    func submitAnswer(
        answerId: String,
        displayedQuestion: CompetitiveDisplayedQuestionContext,
        eventId: String = UUID().uuidString
    ) async throws -> CompetitiveIntentAck {
        guard displayedQuestion.matches(session: session, state: state) else {
            throw CompetitiveServiceError.staleDisplayedQuestion
        }
        return try await send(
            type: "submitAnswer",
            eventId: eventId,
            questionId: displayedQuestion.questionId,
            stateVersion: displayedQuestion.stateVersion,
            payload: ["answerId": answerId]
        )
    }

    func leave(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(type: "leave", eventId: eventId)
    }

    func forfeit(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(type: "forfeit", eventId: eventId)
    }

    /// Background移行など、通信切断を確定できる場合にgrace開始をServerへ通知する。
    func markDisconnected() async throws {
        try await presence().setValue(presencePayload(connected: false))
    }

    /// 同じUID / session fenceで15秒以内に復帰する。新しいmatch sessionは作らない。
    func reconnect(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await registerConnectedPresence()
        return try await send(type: "reconnect", eventId: eventId)
    }

    func reconcile(eventId: String = UUID().uuidString) async throws -> CompetitiveIntentAck {
        try await send(
            type: "reconcile",
            eventId: eventId,
            functionName: "competitiveReconcileMatch"
        )
    }

    private func presence() -> DatabaseReference {
        if let presenceReference { return presenceReference }
        let reference = database.child(
            "competitiveV2/presence/\(session.matchId)/\(session.uid)"
        )
        presenceReference = reference
        return reference
    }

    nonisolated static func presencePayload(
        session: CompetitiveSession,
        connected: Bool,
        timestamp: Any
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "connected": connected,
            "matchId": session.matchId,
            "sessionId": session.sessionId,
            "sessionEpoch": session.sessionEpoch,
            "updatedAtEpochMs": timestamp
        ]
        if !connected {
            payload["disconnectedAtEpochMs"] = timestamp
        }
        return payload
    }

    private func presencePayload(connected: Bool) -> [String: Any] {
        Self.presencePayload(
            session: session,
            connected: connected,
            timestamp: ServerValue.timestamp()
        )
    }

    private func registerConnectedPresence() async throws {
        let reference = presence()
        try await reference.onDisconnectSetValue(presencePayload(connected: false))
        try await reference.setValue(presencePayload(connected: true))
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.publicObserver != nil else { return }
                    do {
                        try await self.markDisconnected()
                    } catch {
                        self.listeningError = error
                    }
                }
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.publicObserver != nil else { return }
                    do {
                        _ = try await self.reconnect()
                    } catch {
                        self.listeningError = error
                    }
                }
            },
        ]
    }

    private func send(
        type: String,
        eventId: String,
        questionId: String? = nil,
        stateVersion: Int? = nil,
        payload: [String: Any] = [:],
        functionName: String = "competitiveIntent"
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

        let response = try await functions.httpsCallable(functionName).call(envelope)
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
    @ObservationIgnored nonisolated(unsafe) private var npcFillTask: Task<Void, Never>?

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
        npcFillTask?.cancel()
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
                if let current = self.state,
                   state.sessionEpoch < current.sessionEpoch
                    || (state.sessionEpoch == current.sessionEpoch
                        && state.updatedAtEpochMS < current.updatedAtEpochMS) {
                    return
                }
                self.state = state
                self.listeningError = nil
                if state.state == .queued,
                   let nextCheckAfterMS = state.nextCheckAfterMS,
                   let queuedAtEpochMS = state.queuedAtEpochMS {
                    let nowEpochMS = Date().timeIntervalSince1970 * 1_000
                    self.scheduleNPCFillCheck(
                        afterMilliseconds: max(
                            0,
                            Int(queuedAtEpochMS) + nextCheckAfterMS - Int(nowEpochMS)
                        ),
                        sessionId: state.sessionId,
                        sessionEpoch: state.sessionEpoch
                    )
                } else {
                    self.npcFillTask?.cancel()
                    self.npcFillTask = nil
                }
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
        npcFillTask?.cancel()
        npcFillTask = nil
    }

    func joinQueue(eventId: String = UUID().uuidString) async throws -> CompetitiveMatchmakingAck {
        let result = try await send([
            "intentId": eventId,
            "type": "joinQueue",
            "protocolVersion": CompetitiveService.protocolVersion,
            "clientBuild": CompetitiveService.clientBuild,
            "payload": [:]
        ])
        if result.status != .rejected,
           result.matchmakingState == .queued,
           let sessionId = result.sessionId,
           let sessionEpoch = result.sessionEpoch,
           let nextCheckAfterMs = result.nextCheckAfterMs,
           nextCheckAfterMs > 0 {
            scheduleNPCFillCheck(
                afterMilliseconds: nextCheckAfterMs,
                sessionId: sessionId,
                sessionEpoch: sessionEpoch
            )
        }
        return result
    }

    private func scheduleNPCFillCheck(
        afterMilliseconds: Int,
        sessionId: String,
        sessionEpoch: Int
    ) {
        if let state,
           state.sessionId == sessionId,
           state.sessionEpoch == sessionEpoch,
           npcFillTask != nil {
            return
        }
        npcFillTask?.cancel()
        npcFillTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(afterMilliseconds) * 1_000_000)
                guard !Task.isCancelled, let self else { return }
                _ = try await self.send([
                    "intentId": UUID().uuidString,
                    "type": "checkQueue",
                    "protocolVersion": CompetitiveService.protocolVersion,
                    "clientBuild": CompetitiveService.clientBuild,
                    "sessionId": sessionId,
                    "sessionEpoch": sessionEpoch,
                    "payload": [:]
                ])
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.listeningError = error
            }
        }
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
