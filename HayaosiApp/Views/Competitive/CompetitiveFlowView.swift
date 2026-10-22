import SwiftUI

struct CompetitiveFlowView: View {
    @State private var coordinator = CompetitiveClientCoordinator()

    var body: some View {
        Group {
            switch screen {
            case .home:
                CompetitiveHomeView(
                    profile: coordinator.profile,
                    isLoading: coordinator.isLoading || coordinator.isQueueOperationInFlight,
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
            matchmakingState: coordinator.matchmakingService?.state?.state,
            hasActiveMatch: coordinator.battleService != nil
        )
    }
}

#Preview {
    NavigationStack {
        CompetitiveFlowView()
    }
}
