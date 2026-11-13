import SwiftUI

struct CompetitiveMatchmakingView: View {
    let projection: CompetitiveMatchmakingProjection?
    let isOperationInFlight: Bool
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.secondary)

                    VStack(spacing: 14) {
                        Text(headline)
                            .font(.title2.bold())
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: 22) {
                    if CompetitiveClientDisplay.canCancelQueue(projection?.state) {
                        Button(action: onCancel) {
                            Text("検索をキャンセル")
                                .font(.headline)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 24)
                                .frame(minHeight: 48)
                                .background(
                                    Color(.systemGray5),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isOperationInFlight)
                    }

                    Text("しばらく待つと、NPCで補充される場合があります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("マッチング")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var backgroundColor: Color { Color(.systemGroupedBackground) }

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
