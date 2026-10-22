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
    var userMessage: String?

    private var preparationTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?

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
        battleService?.stopListening()
        battleService = nil
        activeSession = nil
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
        battleService?.stopListening()
        battleService = nil
        activeSession = nil
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
        if state.phase == .settled { return true }
        return state.phase == .matchFinished && state.finalResult?.outcome != "COMPLETED"
    }

    private func activate(_ session: CompetitiveSession) {
        let newKey = CompetitiveSessionKey(session: session)
        guard activeSessionKey != newKey else { return }
        preparationTask?.cancel()
        reconcileTask?.cancel()
        battleService?.stopListening()

        activeSession = session
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

        let dueEpochMS: Double?
        switch state.phase {
        case .countdown:
            dueEpochMS = state.countdownEndsAtEpochMS
        case .questionOpen:
            dueEpochMS = state.currentQuestion?.deadlineEpochMS
        case .questionResult:
            dueEpochMS = state.resultEndsAtEpochMS
        case .nextQuestion, .matchFinished, .settlementPending:
            dueEpochMS = 0
        case .created, .waitingPlayers, .settled:
            dueEpochMS = nil
        }
        guard let dueEpochMS else { return }

        let nowEpochMS = Date().timeIntervalSince1970 * 1_000
        let delayMS = max(0, Int(dueEpochMS - nowEpochMS)) + 100
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
}
