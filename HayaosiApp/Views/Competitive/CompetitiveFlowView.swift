import SwiftUI

struct CompetitiveBadgeEvolutionRequest: Equatable, Identifiable {
    let id = UUID()
    let tier: CompetitiveTier
}

struct CompetitiveFlowView: View {
    @State private var coordinator = CompetitiveClientCoordinator()
    @State private var badgeEvolutionRequest: CompetitiveBadgeEvolutionRequest?

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
                    onBadgeEvolutionHandled: { requestID in
                        guard badgeEvolutionRequest?.id == requestID else { return }
                        badgeEvolutionRequest = nil
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
        }
        .onChange(of: coordinator.battleService?.state) { _, _ in
            coordinator.handleBattleProjection()
        }
        .onChange(of: coordinator.profile) { previous, current in
            guard screen == .match,
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
}

#Preview {
    NavigationStack {
        CompetitiveFlowView()
    }
}
