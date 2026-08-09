import SwiftUI
import SwiftData

/// 対戦のコンテナ(オンライン・CPU共通)。ルーム状態(待機/対戦中/リザルト/解散)で画面を切り替える
struct BattleFlowView: View {
    private static let startCueTickInterval: TimeInterval = 0.05

    let session: any BattleSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showLeaveDialog = false
    @State private var matchStartObservedAt: Date?

    var body: some View {
        Group {
            switch session.state?.status {
            case .waiting:
                BattleLobbyView(session: session)
            case .playing:
                playingView
            case .finished:
                BattleResultView(session: session, onLeave: leaveAndDismiss)
            case .closed:
                closedView(message: "ホストが退出したため、ルームは解散しました")
            case nil:
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        // ロビーからリザルトまでタブバーを隠す。対戦中に他タブへ抜けられると
        // ルームに残ったまま迷子になるため、退出はツールバーの「退出」に一本化する
        .toolbar(.hidden, for: .tabBar)
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
        .onAppear {
            updateMatchStartObservation(for: session.state?.status)
        }
        .onChange(of: session.state?.status) { _, newStatus in
            updateMatchStartObservation(for: newStatus)
            if newStatus == .finished {
                SoundPlayer.shared.play(.fanfare)
                session.saveResultsIfNeeded(context: modelContext)
            }
        }
    }

    @ViewBuilder
    private var playingView: some View {
        if let game = session.state?.game,
           game.questionIndex == 0,
           game.phase == .question,
           game.startDelayMS > 0,
           let observedAt = matchStartObservedAt {
            TimelineView(.periodic(from: .now, by: Self.startCueTickInterval)) { timeline in
                let remaining = BattleStartTiming.remainingDisplayTime(
                    scheduledStartAtMS: game.effectiveStartedAtMS,
                    observedAt: observedAt,
                    now: timeline.date
                )
                if remaining > 0 {
                    BattleStartView(progress: BattleStartTiming.progress(
                        scheduledStartAtMS: game.effectiveStartedAtMS,
                        observedAt: observedAt,
                        now: timeline.date
                    ))
                } else {
                    BattleView(session: session)
                }
            }
        } else if (session.state?.game?.startDelayMS ?? 0) > 0,
                  matchStartObservedAt == nil {
            BattleStartView(progress: 0)
        } else {
            BattleView(session: session)
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

    private func updateMatchStartObservation(for status: RoomState.Status?) {
        if status == .playing {
            matchStartObservedAt = matchStartObservedAt ?? .now
        } else {
            matchStartObservedAt = nil
        }
    }
}
