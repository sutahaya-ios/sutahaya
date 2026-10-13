import SwiftUI

/// 得点順の参加者を表彰台と一覧に分ける。採点・同順位の規則は共通の計算を使う。
struct BattleResultPodiumView: View {
    let players: [RoomState.Player]
    let myID: String

    private static let podiumCount = 3
    private static let twoPlayerHeight: CGFloat = 200
    private static let multiplayerHeight: CGFloat = 110
    private static let rankHeightDifference: CGFloat = 25

    var body: some View {
        VStack(spacing: 24) {
            Text(outcome).font(.title.bold())
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(podiumPlayers) { player in
                    podiumColumn(player)
                }
            }
            if players.count > Self.podiumCount {
                VStack(spacing: 4) {
                    ForEach(Array(players.dropFirst(Self.podiumCount))) { player in
                        rankingRow(player)
                    }
                }
            }
        }
    }

    private var outcome: String {
        guard let me = players.first(where: { $0.id == myID }) else { return "対戦終了" }
        let myRank = rank(me)
        guard myRank == 1 else { return "\(myRank)位" }
        return players.filter { $0.score == me.score }.count > 1 ? "同点1位" : "あなたの勝利！"
    }

    private var podiumPlayers: [RoomState.Player] {
        let leaders = Array(players.prefix(Self.podiumCount))
        guard leaders.count > 1 else { return leaders }
        return [leaders[1], leaders[0]] + Array(leaders.dropFirst(2))
    }

    private func rank(_ player: RoomState.Player) -> Int {
        BattleRanking.rank(of: player, in: players)
    }

    private func podiumColumn(_ player: RoomState.Player) -> some View {
        VStack(spacing: 10) {
            Image(systemName: rank(player) == 1 ? "crown.fill" : "person.fill")
                .font(.title2)
                .foregroundStyle(player.id == myID ? Color.blue : Color.secondary)
                .accessibilityHidden(true)
            Text(player.nickname)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(player.score) pt").font(.headline).monospacedDigit()
            VStack(spacing: 8) {
                Text("\(rank(player))位").font(.title2.bold())
                if player.id == myID { Text("自分").font(.caption) }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: podiumHeight(player))
            .background(
                player.id == myID ? Color.blue.opacity(0.14) : Color(.secondarySystemBackground),
                in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank(player))位、\(player.nickname)、\(player.score)ポイント\(player.id == myID ? "、自分" : "")")
    }

    private func podiumHeight(_ player: RoomState.Player) -> CGFloat {
        let base = players.count == 2 ? Self.twoPlayerHeight : Self.multiplayerHeight
        return base - CGFloat(rank(player) - 1) * Self.rankHeightDifference
    }

    private func rankingRow(_ player: RoomState.Player) -> some View {
        HStack(spacing: 10) {
            Text("\(rank(player))位").fontWeight(.semibold)
            Text(player.nickname).lineLimit(2)
            if player.id == myID {
                Text("自分").font(.caption2).foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
            Text("\(player.score) pt").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            player.id == myID ? Color.blue.opacity(0.10) : .clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}
