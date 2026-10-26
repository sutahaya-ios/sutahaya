import Foundation
import Observation

@MainActor
@Observable
final class CompetitiveClientCoordinator {
    private(set) var matchmakingService: CompetitiveMatchmakingService?
    private(set) var battleService: CompetitiveService?
    private(set) var activeSession: CompetitiveSession?
    private(set) var isLoading = false
    private(set) var isQueueOperationInFlight = false
    private(set) var isPreparingMatch = false
    private(set) var isSubmittingAnswer = false
    private(set) var isForfeitSending = false
    private(set) var isSettlementRecoveryDelayed = false
    private(set) var resultReadySessionKey: CompetitiveSessionKey?
    var userMessage: String?

    private var preparationTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var settlementRecoveryTask: Task<Void, Never>?
    private var settledProfileRefreshTask: Task<Void, Never>?

    var profile: CompetitiveProfileProjection? {
        matchmakingService?.state?.competitive
    }

    var activeSessionKey: CompetitiveSessionKey? {
        activeSession.map { CompetitiveSessionKey(session: $0) }
    }

    func start() async {
        guard matchmakingService == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let uid = try await AuthService.shared.ensureAuthenticated()
            let service = CompetitiveMatchmakingService(uid: uid)
            matchmakingService = service
            service.observeMatchmakingState()
        } catch {
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func stop() {
        preparationTask?.cancel()
        preparationTask = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        settlementRecoveryTask?.cancel()
        settlementRecoveryTask = nil
        settledProfileRefreshTask?.cancel()
        settledProfileRefreshTask = nil
        battleService?.stopListening()
        battleService = nil
        activeSession = nil
        resultReadySessionKey = nil
        isSettlementRecoveryDelayed = false
        matchmakingService?.stopObservingMatchmakingState()
        matchmakingService = nil
    }

    func handleMatchmakingProjection() {
        guard let session = matchmakingService?.state?.competitiveSession else { return }
        activate(session)
    }

    func joinQueue() async {
        guard let matchmakingService, !isQueueOperationInFlight else { return }
        isQueueOperationInFlight = true
        userMessage = nil
        defer { isQueueOperationInFlight = false }
        do {
            let result = try await matchmakingService.joinQueue()
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func cancelQueue() async {
        guard let matchmakingService,
              CompetitiveClientDisplay.canCancelQueue(matchmakingService.state?.state),
              !isQueueOperationInFlight else { return }
        isQueueOperationInFlight = true
        userMessage = nil
        defer { isQueueOperationInFlight = false }
        do {
            let result = try await matchmakingService.cancelQueue()
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func handleBattleProjection() {
        guard let battleService, let activeSession else { return }
        let expectedKey = CompetitiveSessionKey(session: activeSession)
        guard activeSessionKey == expectedKey,
              battleService.state?.matchId == activeSession.matchId else { return }

        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            await self?.prepareMatchIfNeeded(expectedKey: expectedKey)
        }
        handleSettlementProjection(expectedKey: expectedKey)
        scheduleReconcileIfNeeded(expectedKey: expectedKey)
    }

    func submitAnswer(
        answerId: String,
        displayedQuestion: CompetitiveDisplayedQuestionContext
    ) async {
        guard let battleService,
              activeSessionKey == displayedQuestion.sessionKey,
              !isSubmittingAnswer else { return }
        isSubmittingAnswer = true
        userMessage = nil
        defer { isSubmittingAnswer = false }
        do {
            let result = try await battleService.submitAnswer(
                answerId: answerId,
                displayedQuestion: displayedQuestion
            )
            guard activeSessionKey == displayedQuestion.sessionKey else { return }
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            guard activeSessionKey == displayedQuestion.sessionKey else { return }
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func forfeit() async {
        guard let battleService,
              let expectedKey = activeSessionKey,
              !isForfeitSending else { return }
        isForfeitSending = true
        userMessage = nil
        defer { isForfeitSending = false }
        do {
            let result = try await battleService.forfeit()
            guard activeSessionKey == expectedKey else { return }
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            guard activeSessionKey == expectedKey else { return }
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func retryConnection() async {
        guard let battleService,
              let expectedKey = activeSessionKey else { return }
        userMessage = nil
        battleService.startListening()
        do {
            let result = try await battleService.reconnect()
            guard activeSessionKey == expectedKey else { return }
            if result.status == .rejected,
               result.rejectionCode != "NOT_RECONNECTING" {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            guard activeSessionKey == expectedKey else { return }
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    func returnHome() {
        guard canLeaveResult else { return }
        preparationTask?.cancel()
        reconcileTask?.cancel()
        settlementRecoveryTask?.cancel()
        settledProfileRefreshTask?.cancel()
        battleService?.stopListening()
        battleService = nil
        activeSession = nil
        resultReadySessionKey = nil
        isSettlementRecoveryDelayed = false
    }

    func playAgain() async {
        guard canLeaveResult else { return }
        returnHome()
        await joinQueue()
    }

    func leaveBeforeCommitment() async {
        guard let battleService,
              battleService.state?.phase == .waitingPlayers,
              let expectedKey = activeSessionKey else { return }
        isForfeitSending = true
        userMessage = nil
        defer { isForfeitSending = false }
        do {
            let result = try await battleService.leave()
            guard activeSessionKey == expectedKey else { return }
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch {
            guard activeSessionKey == expectedKey else { return }
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    var canLeaveResult: Bool {
        guard let state = battleService?.state else { return false }
        if state.phase == .settled || resultReadySessionKey == activeSessionKey { return true }
        return state.phase == .matchFinished && state.finalResult?.outcome != "COMPLETED"
    }

    func retrySettlementRecovery() {
        guard let expectedKey = activeSessionKey,
              CompetitiveSettlementRecoveryPolicy.action(
                for: battleService?.state,
                sessionKey: expectedKey
              ) == .refreshAndReconcile else { return }
        settlementRecoveryTask?.cancel()
        settlementRecoveryTask = nil
        isSettlementRecoveryDelayed = false
        startSettlementRecovery(expectedKey: expectedKey)
    }

    private func activate(_ session: CompetitiveSession) {
        let newKey = CompetitiveSessionKey(session: session)
        guard activeSessionKey != newKey else { return }
        preparationTask?.cancel()
        reconcileTask?.cancel()
        settlementRecoveryTask?.cancel()
        settledProfileRefreshTask?.cancel()
        battleService?.stopListening()

        activeSession = session
        resultReadySessionKey = nil
        isSettlementRecoveryDelayed = false
        let service = CompetitiveService(session: session)
        battleService = service
        service.startListening()
    }

    private func prepareMatchIfNeeded(expectedKey: CompetitiveSessionKey) async {
        guard !isPreparingMatch,
              let service = battleService,
              let session = activeSession,
              activeSessionKey == expectedKey,
              let state = service.state,
              state.matchId == session.matchId,
              state.phase == .waitingPlayers,
              let participant = state.participants.first(where: { $0.uid == session.uid })
        else { return }

        isPreparingMatch = true
        defer { isPreparingMatch = false }
        do {
            if !participant.joined {
                let result = try await service.joinMatch()
                guard activeSessionKey == expectedKey else { return }
                if result.status == .rejected {
                    userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
                    return
                }
                await Task.yield()
            }

            guard activeSessionKey == expectedKey,
                  let latest = service.state,
                  latest.phase == .waitingPlayers,
                  let latestParticipant = latest.participants.first(where: { $0.uid == session.uid }),
                  latestParticipant.joined,
                  !latestParticipant.ready else { return }
            let result = try await service.ready()
            guard activeSessionKey == expectedKey else { return }
            if result.status == .rejected {
                userMessage = CompetitiveClientDisplay.rejectionMessage(result.rejectionCode)
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeSessionKey == expectedKey else { return }
            userMessage = CompetitiveClientDisplay.userMessage(for: error)
        }
    }

    private func scheduleReconcileIfNeeded(expectedKey: CompetitiveSessionKey) {
        reconcileTask?.cancel()
        guard let state = battleService?.state else { return }

        guard let activeSession,
              let dueEpochMS = CompetitiveReconcileSchedule.dueEpochMS(
                for: state,
                actorUID: activeSession.uid
              ) else {
            return
        }

        let nowEpochMS = Date().timeIntervalSince1970 * 1_000
        let delayMS = max(0, Int(dueEpochMS - nowEpochMS)) + 50
        reconcileTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMS))
                guard !Task.isCancelled,
                      let self,
                      self.activeSessionKey == expectedKey,
                      let service = self.battleService else { return }
                let result = try await service.reconcile()
                guard self.activeSessionKey == expectedKey else { return }
                if result.status == .rejected, result.rejectionCode != "INVALID_MATCH_STATE" {
                    self.userMessage = CompetitiveClientDisplay.rejectionMessage(
                        result.rejectionCode
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeSessionKey == expectedKey else { return }
                self.userMessage = CompetitiveClientDisplay.userMessage(for: error)
            }
        }
    }

    private func handleSettlementProjection(expectedKey: CompetitiveSessionKey) {
        switch CompetitiveSettlementRecoveryPolicy.action(
            for: battleService?.state,
            sessionKey: expectedKey
        ) {
        case .none:
            settlementRecoveryTask?.cancel()
            settlementRecoveryTask = nil
            isSettlementRecoveryDelayed = false
        case .refreshAndReconcile:
            startSettlementRecovery(expectedKey: expectedKey)
        case .complete:
            markSettlementComplete(expectedKey: expectedKey)
        }
    }

    private func startSettlementRecovery(expectedKey: CompetitiveSessionKey) {
        guard settlementRecoveryTask == nil else { return }
        settlementRecoveryTask = Task { [weak self] in
            await self?.recoverSettlement(expectedKey: expectedKey)
        }
    }

    private func recoverSettlement(expectedKey: CompetitiveSessionKey) async {
        var attempt = 0
        while !Task.isCancelled {
            guard activeSessionKey == expectedKey, let service = battleService else { return }

            do {
                _ = try await service.refreshState()
            } catch {
                // Reconcileと次回readで回復を続ける。rating/statsはClientで推測しない。
            }

            switch CompetitiveSettlementRecoveryPolicy.action(
                for: service.state,
                sessionKey: expectedKey
            ) {
            case .complete:
                markSettlementComplete(expectedKey: expectedKey)
                return
            case .none:
                settlementRecoveryTask = nil
                return
            case .refreshAndReconcile:
                do {
                    _ = try await service.reconcile()
                } catch {
                    // 一時失敗でもServer projectionの再取得を継続する。
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, activeSessionKey == expectedKey else { return }
                _ = try await service.refreshState()
                if CompetitiveSettlementRecoveryPolicy.action(
                    for: service.state,
                    sessionKey: expectedKey
                ) == .complete {
                    markSettlementComplete(expectedKey: expectedKey)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                // 次のretryで再取得する。
            }

            attempt += 1
            isSettlementRecoveryDelayed = CompetitiveSettlementRecoveryPolicy.isDelayed(
                attempt: attempt
            )
            do {
                try await Task.sleep(
                    for: .milliseconds(
                        CompetitiveSettlementRecoveryPolicy.retryDelayMilliseconds
                    )
                )
            } catch {
                return
            }
        }
    }

    private func markSettlementComplete(expectedKey: CompetitiveSessionKey) {
        guard activeSessionKey == expectedKey else { return }
        settlementRecoveryTask?.cancel()
        settlementRecoveryTask = nil
        isSettlementRecoveryDelayed = false
        guard CompetitiveSettlementRecoveryPolicy.shouldCompleteResult(
            action: .complete,
            completedSessionKey: resultReadySessionKey,
            expectedSessionKey: expectedKey
        ) else { return }
        resultReadySessionKey = expectedKey
        refreshSettledProfile(expectedKey: expectedKey)
    }

    private func refreshSettledProfile(expectedKey: CompetitiveSessionKey) {
        settledProfileRefreshTask?.cancel()
        settledProfileRefreshTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<3 {
                guard !Task.isCancelled,
                      self.activeSessionKey == expectedKey,
                      let matchmakingService = self.matchmakingService else { return }
                do {
                    _ = try await matchmakingService.refreshState()
                    return
                } catch where attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
        }
    }
}
