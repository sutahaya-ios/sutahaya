import SwiftUI

/// 対戦タブの主役として「誰と遊ぶか」を一目で選べる大きなカード
struct BattleModeCard: View {
    private static let cornerRadius: CGFloat = 22
    private static let iconSize: CGFloat = 48

    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(Circle().fill(color))

            Spacer(minLength: 8)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(color.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}

#Preview {
    HStack {
        BattleModeCard(
            title: "ひとりで",
            subtitle: "CPUと対戦\n通信なしですぐ遊べる",
            systemImage: "person.fill",
            color: .orange
        )
        BattleModeCard(
            title: "オンライン",
            subtitle: "友達と対戦\nルームを作成・参加",
            systemImage: "person.2.fill",
            color: .blue
        )
    }
    .padding()
}
