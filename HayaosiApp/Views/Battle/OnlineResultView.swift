import SwiftUI

/// 対戦リザルト:ポイント順の順位表示(同点は同順位)と再戦(要件 §5.1.3・§9-6)
struct OnlineResultView: View {
    let session: any BattleSession
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("対戦結果")
                .font(.title.bold())

            List {
                ForEach(rankedPlayers) { player in
                    HStack(spacing: 12) {
                        Text("\(rank(of: player))位")
                            .font(.headline)
                            .frame(width: 44, alignment: .leading)
                        Text(player.nickname)
                            .fontWeight(player.id == session.myID ? .bold : .regular)
                        if player.id == session.myID {
                            Text("(自分)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(player.score)pt")
                            .monospacedDigit()
                    }
                    .listRowBackground(
                        player.id == session.myID ? Color.accentColor.opacity(0.1) : nil
                    )
                }
            }
            .listStyle(.insetGrouped)

            VStack(spacing: 12) {
                if session.isHost {
                    Button(session.isOnline ? "再戦する(ロビーに戻る)" : "もう一度対戦する") {
                        Task { await session.rematch() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("ホストが再戦を選ぶとロビーに戻ります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("退出") {
                    onLeave()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical)
        .navigationTitle("リザルト")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rankedPlayers: [RoomState.Player] {
        (session.state?.players ?? []).sorted { $0.score > $1.score }
    }

    /// 同点は同順位(要件 §5.1.3)
    private func rank(of player: RoomState.Player) -> Int {
        rankedPlayers.filter { $0.score > player.score }.count + 1
    }
}
