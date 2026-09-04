import SwiftUI

/// 対戦数・1位回数・1位率の3指標。プロフィールカードと詳細画面で同じ見た目を使う
struct BattleStatsRow: View {
    let stats: ProfileBattleStats

    var body: some View {
        HStack(spacing: 0) {
            metric(
                value: String(stats.battleCount),
                title: "対戦数",
                systemImage: "gamecontroller.fill",
                color: .indigo
            )

            divider

            metric(
                value: String(stats.firstPlaceCount),
                title: "1位回数",
                systemImage: "crown.fill",
                color: .yellow
            )

            divider

            metric(
                value: stats.firstPlaceRateText,
                title: "1位率",
                systemImage: "trophy.fill",
                color: .blue
            )
        }
    }

    private var divider: some View {
        Divider()
            .frame(height: 60)
    }

    private func metric(value: String, title: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BattleStatsRow(stats: ProfileBattleStats(battleCount: 42, firstPlaceCount: 18))
        .padding()
}
