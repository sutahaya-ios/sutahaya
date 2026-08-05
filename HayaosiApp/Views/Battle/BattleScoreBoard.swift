import SwiftUI

/// 対戦画面上部のスコア表示。得点が動いた瞬間が分かるよう、数字と枠に変化を付ける
struct BattleScoreBoard: View {
    private static let cardCorner: CGFloat = 10
    private static let scorerScale: CGFloat = 1.06

    let players: [RoomState.Player]
    let myID: String
    /// 直前に得点したプレイヤー(正解発表中のみ)。カードを強調する
    let scorerID: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(players) { player in
                card(for: player)
            }
        }
    }

    private func card(for player: RoomState.Player) -> some View {
        let isScorer = player.id == scorerID
        return VStack(spacing: 4) {
            Text(player.nickname)
                .font(.caption)
                .lineLimit(1)
            Text("\(player.score)pt")
                .font(.headline)
                .monospacedDigit()
                // 得点が動いたときに数字が入れ替わって見える(iOS 17+)
                .contentTransition(.numericText(value: Double(player.score)))
                .foregroundStyle(isScorer ? Color.green : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(background(for: player, isScorer: isScorer))
        .scaleEffect(isScorer ? Self.scorerScale : 1)
        .animation(BattleAnimation.scoreChange, value: player.score)
        .animation(BattleAnimation.scoreChange, value: isScorer)
    }

    private func background(for player: RoomState.Player, isScorer: Bool) -> some View {
        RoundedRectangle(cornerRadius: Self.cardCorner)
            .fill(fillColor(for: player, isScorer: isScorer))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCorner)
                    .strokeBorder(Color.green, lineWidth: isScorer ? 2 : 0)
            )
    }

    private func fillColor(for player: RoomState.Player, isScorer: Bool) -> Color {
        if isScorer { return .green.opacity(0.18) }
        return player.id == myID ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)
    }
}

#Preview {
    BattleScoreBoard(
        players: [
            .init(id: "me", nickname: "ゲスト", score: 3, joinedAtMS: 0),
            .init(id: "bot", nickname: "ボット(強)", score: 5, joinedAtMS: 1)
        ],
        myID: "me",
        scorerID: "bot"
    )
    .padding()
}
