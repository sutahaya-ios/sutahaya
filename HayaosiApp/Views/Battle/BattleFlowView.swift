import SwiftUI
import SwiftData

/// 対戦のコンテナ(オンライン・CPU共通)。ルーム状態(待機/対戦中/リザルト/解散)で画面を切り替える
struct BattleFlowView: View {
    let session: any BattleSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showLeaveDialog = false

    var body: some View {
        Group {
            switch session.state?.status {
            case .waiting:
                BattleLobbyView(session: session)
            case .playing:
                BattleView(session: session)
            case .finished:
                BattleResultView(session: session, onLeave: leaveAndDismiss)
            case .closed:
                closedView(message: "ホストが退出したため、ルームは解散しました")
            case nil:
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if session.state?.status != .finished && session.state?.status != .closed {
                ToolbarItem(placement: .topBarLeading) {
                    Button("退出") {
                        if session.state?.status == .playing {
                            showLeaveDialog = true
                        } else {
                            leaveAndDismiss()
                        }
                    }
                }
            }
        }
        .confirmationDialog("対戦から退出しますか?", isPresented: $showLeaveDialog, titleVisibility: .visible) {
            Button("退出する", role: .destructive) {
                leaveAndDismiss()
            }
        } message: {
            if !session.isOnline {
                Text("対戦を終了します")
            } else if session.isHost {
                Text("ホストが退出するとルームは解散されます")
            } else {
                Text("対戦の途中で抜けます")
            }
        }
        .onChange(of: session.state?.status) { _, newStatus in
            if newStatus == .finished {
                SoundPlayer.shared.play(.fanfare)
                session.saveResultsIfNeeded(context: modelContext)
            }
        }
    }

    private func closedView(message: String) -> some View {
        ContentUnavailableView {
            Label("ルーム解散", systemImage: "door.left.hand.open")
        } description: {
            Text(message)
        } actions: {
            Button("戻る") {
                leaveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func leaveAndDismiss() {
        session.leave()
        dismiss()
    }
}
