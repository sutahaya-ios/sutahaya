import SwiftUI

/// 1問目の前に表示する、CPU・オンライン共通の開始合図。
/// 参加者を正多角形の頂点に置き、中央にVSを1つ出す
struct BattleStartView: View {
    let players: [RoomState.Player]
    let myID: String

    /// 頂点を置く円の半径
    private static let radius: CGFloat = 92
    /// これを超える人数では名前を出さない(間隔が詰まって重なるため)
    private static let nameLimit = 5
    private static let largeAvatar: CGFloat = 46
    private static let smallAvatar: CGFloat = 34

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if players.isEmpty {
                Text("対戦開始")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            } else {
                ZStack {
                    versusMark
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        participant(player)
                            .offset(offset(at: index))
                    }
                }
                .frame(width: Self.radius * 2 + Self.largeAvatar, height: Self.radius * 2 + Self.largeAvatar)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("対戦")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("対戦開始")
    }

    private var versusMark: some View {
        Text("VS")
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .italic()
            .foregroundStyle(.primary)
            .shadow(color: .blue.opacity(0.6), radius: 12)
    }

    private func participant(_ player: RoomState.Player) -> some View {
        let isMe = player.id == myID
        return VStack(spacing: 4) {
            AvatarCircle(
                name: player.nickname,
                size: showsNames ? Self.largeAvatar : Self.smallAvatar,
                color: isMe ? .blue : AvatarCircle.stableColor(for: player.id)
            )
            if showsNames {
                Text(player.nickname)
                    .font(.caption2)
                    .fontWeight(isMe ? .bold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: 76)
            }
        }
    }

    private var showsNames: Bool { players.count <= Self.nameLimit }

    /// 円周上の等間隔。`startAngle` だけ人数で例外を持つ
    private func offset(at index: Int) -> CGSize {
        let angle = startAngle + (2 * .pi / Double(players.count)) * Double(index)
        return CGSize(width: Self.radius * cos(angle), height: Self.radius * sin(angle))
    }

    private var startAngle: Double {
        switch players.count {
        // 上下に並べると縦に間延びするので、2人だけ左右へ置く
        case 2: .pi
        // 頂点を上にするとひし形になり、縦長の画面では横幅が余る。45度回して正方形にする
        case 4: -3 * .pi / 4
        default: -.pi / 2
        }
    }
}

#Preview("2人") {
    NavigationStack {
        BattleStartView(players: previewPlayers(count: 2), myID: "me")
    }
}

#Preview("5人") {
    NavigationStack {
        BattleStartView(players: previewPlayers(count: 5), myID: "me")
    }
}

#Preview("8人") {
    NavigationStack {
        BattleStartView(players: previewPlayers(count: 8), myID: "me")
    }
}

private func previewPlayers(count: Int) -> [RoomState.Player] {
    (0..<count).map { index in
        let isMe = index == 0
        let id: String = isMe ? "me" : "cpu-\(index)"
        let nickname: String = isMe ? "ゲスト" : "CPU\(index)"
        return RoomState.Player(id: id, nickname: nickname, score: 0, joinedAtMS: Double(index))
    }
}
