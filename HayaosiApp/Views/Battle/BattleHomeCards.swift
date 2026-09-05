import SwiftUI

/// 対戦ホーム上部の世界観を作る装飾。操作要素にはしない。
struct BattleHomeHero: View {
    private static let heroHeight: CGFloat = 224
    private static let emblemSize: CGFloat = 108

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.14),
                    Color.accentColor.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            cloud(width: 104, opacity: 0.72)
                .offset(x: -108, y: -56)
            cloud(width: 76, opacity: 0.5)
                .offset(x: 122, y: -16)
            cloud(width: 126, opacity: 0.8)
                .offset(x: -88, y: 62)

            VStack(spacing: 12) {
                emblem
                    .frame(width: Self.emblemSize, height: Self.emblemSize)

                Text("バトル開始")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.heroHeight)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var emblem: some View {
        ZStack {
            sword
                .rotationEffect(.degrees(-45))
            sword
                .rotationEffect(.degrees(45))

            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .frame(width: 74, height: 84)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }

            Image(systemName: "crown.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.orange.opacity(0.9))
                .offset(y: -54)
        }
    }

    private var sword: some View {
        VStack(spacing: -1) {
            Capsule()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 10, height: 66)
            Capsule()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 34, height: 7)
            Capsule()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 8, height: 21)
        }
    }

    private func cloud(width: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color(.systemBackground).opacity(opacity))
            .frame(width: width, height: 30)
            .blur(radius: 0.5)
    }
}

/// 対戦ホームの2つの主操作を同じ見た目で描画する。
struct BattleModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 31, weight: .semibold))

                Text(title)
                    .font(.headline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(SoundButtonStyle())
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 18) {
            BattleHomeHero()
            HStack(spacing: 12) {
                BattleModeButton(
                    title: "オンライン対戦",
                    subtitle: "全国のプレイヤーと対戦！",
                    systemImage: "globe",
                    action: {}
                )
                BattleModeButton(
                    title: "フレンド対戦",
                    subtitle: "友だちと対戦！",
                    systemImage: "person.2.fill",
                    action: {}
                )
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
