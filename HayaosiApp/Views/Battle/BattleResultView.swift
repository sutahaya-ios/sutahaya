import SwiftUI

/// 対戦リザルト:ポイント順の順位表示(同点は同順位)と再戦(要件 §5.1.3・§9-6)
struct BattleResultView: View {
    let session: any BattleSession
    let onLeave: () -> Void
    @State private var isReviewPresented = false

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

                if !session.wrongQuestionIDs.isEmpty {
                    Button("間違えた\(session.wrongQuestionIDs.count)問を復習") {
                        isReviewPresented = true
                    }
                    .buttonStyle(.bordered)
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
        .sheet(isPresented: $isReviewPresented) {
            NavigationStack {
                ReviewListView(questionIDs: session.wrongQuestionIDs)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { isReviewPresented = false }
                        }
                    }
            }
        }
    }

    private var rankedPlayers: [RoomState.Player] {
        BattleRanking.ranked(session.state?.players ?? [])
    }

    /// 同点は同順位(要件 §5.1.3)。計算はテスト可能な BattleRanking に置く
    private func rank(of player: RoomState.Player) -> Int {
        BattleRanking.rank(of: player, in: rankedPlayers)
    }
}
