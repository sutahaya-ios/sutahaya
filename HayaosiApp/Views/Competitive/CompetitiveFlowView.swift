import SwiftUI

struct CompetitiveBadgeEvolutionRequest: Equatable, Identifiable {
    let id = UUID()
    let tier: CompetitiveTier
}

struct CompetitiveTierChangeAnimationRequest: Equatable, Identifiable {
    let id = UUID()
    let sessionKey: CompetitiveSessionKey
    let tier: CompetitiveTier
    let direction: CompetitiveTierChangeDirection
}

struct CompetitiveFlowView: View {
    @State private var coordinator = CompetitiveClientCoordinator()
    @State private var badgeEvolutionRequest: CompetitiveBadgeEvolutionRequest?
    @State private var tierChangeAnimationRequest: CompetitiveTierChangeAnimationRequest?
    @State private var tierChangeAnimationTracker = CompetitiveTierChangeAnimationTracker()

    var body: some View {
        Group {
            switch screen {
            case .home:
                CompetitiveHomeView(
                    profile: coordinator.profile,
                    isLoading: coordinator.isLoading || coordinator.isQueueOperationInFlight,
                    cooldownEndsAtEpochMS: coordinator.forfeitCooldownEndsAtEpochMS,
                    serverTimeOffsetMS: coordinator.serverTimeOffsetMS,
                    badgeEvolutionRequest: badgeEvolutionRequest,
                    tierChangeAnimationRequest: tierChangeAnimationRequest,
                    onBadgeEvolutionHandled: { requestID in
                        guard badgeEvolutionRequest?.id == requestID else { return }
                        badgeEvolutionRequest = nil
                    },
                    onTierChangeAnimationHandled: { requestID in
                        guard tierChangeAnimationRequest?.id == requestID else { return }
                        tierChangeAnimationRequest = nil
                    },
                    onStart: { Task { await coordinator.joinQueue() } }
                )
            case .matchmaking:
                CompetitiveMatchmakingView(
                    projection: coordinator.matchmakingService?.state,
                    isOperationInFlight: coordinator.isQueueOperationInFlight,
                    onCancel: { Task { await coordinator.cancelQueue() } }
                )
            case .match:
                CompetitiveMatchContainerView(coordinator: coordinator)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await coordinator.start() }
        .onChange(of: coordinator.matchmakingService?.state) { _, _ in
            coordinator.handleMatchmakingProjection()
            if coordinator.screenMatchmakingState == .queued {
                badgeEvolutionRequest = nil
                tierChangeAnimationRequest = nil
            }
        }
        .onChange(of: coordinator.battleService?.state) { _, _ in
            observeTierChangeEligibility()
            coordinator.handleBattleProjection()
            scheduleTierChangeAnimationIfNeeded()
        }
        .onChange(of: coordinator.profile) { previous, current in
            scheduleTierChangeAnimationIfNeeded()
            guard tierChangeAnimationRequest == nil,
                  screen == .match,
                  coordinator.canLeaveResult,
                  CompetitiveClientDisplay.shouldAnimateBadgeEvolution(
                from: previous,
                to: current
            ), let tier = current?.currentTier else { return }
            badgeEvolutionRequest = CompetitiveBadgeEvolutionRequest(tier: tier)
        }
        .onDisappear { coordinator.stop() }
        .alert("ランク戦", isPresented: .init(
            get: { coordinator.userMessage != nil },
            set: { if !$0 { coordinator.userMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.userMessage ?? "")
        }
    }

    private var screen: CompetitiveClientScreen {
        CompetitiveClientScreen.resolve(
            matchmakingState: coordinator.screenMatchmakingState,
            hasActiveMatch: coordinator.battleService != nil
        )
    }

    private func observeTierChangeEligibility() {
        guard let sessionKey = coordinator.activeSessionKey,
              let phase = coordinator.battleService?.state?.phase else { return }
        tierChangeAnimationTracker.observeMatch(sessionKey: sessionKey, phase: phase)
    }

    private func scheduleTierChangeAnimationIfNeeded() {
        guard screen == .match,
              coordinator.canLeaveResult,
              let session = coordinator.activeSession,
              let profile = coordinator.profile,
              let result = coordinator.battleService?.state?.settlement?.playerResults[session.uid],
              result.currentTier == profile.currentTier,
              let direction = tierChangeAnimationTracker.consumeDirection(
                sessionKey: CompetitiveSessionKey(session: session),
                result: result
              ) else { return }
        badgeEvolutionRequest = nil
        tierChangeAnimationRequest = CompetitiveTierChangeAnimationRequest(
            sessionKey: CompetitiveSessionKey(session: session),
            tier: result.currentTier,
            direction: direction
        )
    }
}

#Preview {
    NavigationStack {
        CompetitiveFlowView()
    }
}
