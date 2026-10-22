import SwiftUI

struct CompetitiveMatchmakingView: View {
    let projection: CompetitiveMatchmakingProjection?
    let isOperationInFlight: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(headline)
                .font(.title3.bold())
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            if CompetitiveClientDisplay.canCancelQueue(projection?.state) {
                Button("検索をキャンセル", action: onCancel)
                    .buttonStyle(.bordered)
                    .disabled(isOperationInFlight)
            }
        }
        .padding(24)
        .navigationTitle("マッチング")
        .navigationBarBackButtonHidden(true)
        .background(Color(.systemGroupedBackground))
    }

    private var headline: String {
        switch projection?.state {
        case .matchFound, .waitingPlayers:
            "対戦相手が見つかりました"
        case .queued, .notQueued, nil:
            "対戦相手を探しています"
        }
    }

    private var description: String {
        switch projection?.state {
        case .matchFound, .waitingPlayers:
            "対戦画面を準備しています"
        case .queued, .notQueued, nil:
            "そのままお待ちください"
        }
    }
}
