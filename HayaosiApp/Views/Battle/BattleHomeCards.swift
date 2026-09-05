import SwiftUI

/// 対戦範囲と、その範囲のカテゴリの習得率。数字は学習記録と同じ集計を使う
struct BattleScopeCard: View {
    let categoryName: String
    let difficulty: Int
    let proficiency: CategoryProficiencySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(categoryName)
                    .font(.title3.bold())

                Text("★\(difficulty)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            ProgressView(value: proficiency.progress)
                .tint(Color.accentColor)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("習得率")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(proficiency.rateText)
                    .font(.headline.bold())
                    .monospacedDigit()

                Spacer(minLength: 0)

                Text(proficiency.masteredOverTotalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// 対戦ホームの2つの主操作を同じ見た目で描画する。
struct BattleModeButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 31, weight: .semibold))

                Text(title)
                    .font(.headline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if !isEnabled {
                    Text("乞うご期待")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(
                isEnabled ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(isEnabled ? 0.12 : 0.04), radius: 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if !isEnabled {
                    Text("近日")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .padding(12)
                }
            }
        }
        .buttonStyle(SoundButtonStyle())
        .disabled(!isEnabled)
        .accessibilityHint(isEnabled ? "" : "近日公開、乞うご期待")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 18) {
            BattleScopeCard(
                categoryName: "高校英単語",
                difficulty: 3,
                proficiency: CategoryProficiencySummary.calculate(
                    records: [],
                    questions: [],
                    category: .highSchool
                )
            )
            HStack(spacing: 12) {
                BattleModeButton(
                    title: "オンライン対戦",
                    systemImage: "globe",
                    isEnabled: false,
                    action: {}
                )
                BattleModeButton(
                    title: "フレンド対戦",
                    systemImage: "person.2.fill",
                    action: {}
                )
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
