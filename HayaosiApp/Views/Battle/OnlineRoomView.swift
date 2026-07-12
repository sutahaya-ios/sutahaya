import SwiftUI
import SwiftData

/// オンライン対戦のコンテナ。ルーム状態(待機/対戦中/リザルト/解散)で画面を切り替える
struct OnlineRoomView: View {
    let session: OnlineBattleSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showLeaveDialog = false

    var body: some View {
        Group {
            switch session.state?.status {
            case .waiting:
                OnlineLobbyView(session: session)
            case .playing:
                OnlineBattleView(session: session)
            case .finished:
                OnlineResultView(session: session, onLeave: leaveAndDismiss)
            case .closed:
                closedView(message: "ホストが退出したため、ルームは解散しました")
            case nil:
                if session.state == nil && session.roomCode.isEmpty {
                    ProgressView()
                } else {
                    closedView(message: "ルームへの接続が切れました")
                }
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
            Text(session.isHost ? "ホストが退出するとルームは解散されます" : "対戦の途中で抜けます")
        }
        .onChange(of: session.state?.status) { _, newStatus in
            if newStatus == .finished {
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
