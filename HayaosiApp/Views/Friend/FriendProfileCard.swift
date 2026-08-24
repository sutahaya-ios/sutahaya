import SwiftUI

/// 将来ローカルの対戦結果履歴から集計した戦績を表示するための受け皿。
/// 現在は試合単位の順位履歴がないため、マイページでは `nil` を渡して未集計表示にする。
struct ProfileBattleStats: Equatable {
    let battleCount: Int
    let firstPlaceCount: Int

    var firstPlaceRate: Double {
        guard battleCount > 0 else { return 0 }
        return Double(firstPlaceCount) / Double(battleCount)
    }
}

/// 自分のプロフィールカード。プロフィールを主役にし、戦績とフレンドコードを1枚へまとめる
struct FriendProfileCard: View {
    private static let copiedResetDelay: TimeInterval = 2

    let nickname: String
    let friendCode: String?
    var icon: String = ProfileIcon.none
    var bio: String = ""
    var battleStats: ProfileBattleStats? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            profileHeader
            detailPanel
        }
        .padding(16)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(.separator).opacity(colorScheme == .dark ? 0.55 : 0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            AvatarCircle(name: nickname, icon: icon, size: 74, color: .accentColor)
                .padding(5)
                .background(Circle().fill(Color(.systemBackground).opacity(0.92)))

            VStack(alignment: .leading, spacing: 8) {
                Text(nickname)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(bio.isEmpty ? "自己紹介はまだありません" : bio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var detailPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                metric(
                    value: battleStats.map { String($0.battleCount) } ?? "—",
                    title: "対戦数",
                    systemImage: "gamecontroller.fill",
                    color: .indigo
                )

                metricDivider

                metric(
                    value: battleStats.map { String($0.firstPlaceCount) } ?? "—",
                    title: "1位回数",
                    systemImage: "crown.fill",
                    color: .yellow
                )

                metricDivider

                metric(
                    value: battleStats.map {
                        $0.firstPlaceRate.formatted(.percent.precision(.fractionLength(1)))
                    } ?? "—",
                    title: "1位率",
                    systemImage: "trophy.fill",
                    color: .blue
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("フレンドコード")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                HStack(spacing: 10) {
                    Text(friendCode ?? "------")
                        .font(.system(.headline, design: .monospaced).bold())
                        .foregroundStyle(.primary)
                        .kerning(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.07))
                        )

                    if let friendCode {
                        Button {
                            copy(friendCode)
                        } label: {
                            Label(copied ? "済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption)
                        .fixedSize()

                        ShareLink(item: "スタはやでフレンドになろう!マイコード:\(friendCode)") {
                            Label("シェア", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption)
                        .fixedSize()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color(.secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var metricDivider: some View {
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

    private func copy(_ friendCode: String) {
        UIPasteboard.general.string = friendCode
        copied = true
        Task {
            do {
                try await Task.sleep(for: .seconds(Self.copiedResetDelay))
            } catch {
                return
            }
            copied = false
        }
    }
}

#Preview {
    FriendProfileCard(
        nickname: "TOKIYA TEST DEMO",
        friendCode: "VH49YR",
        icon: "✏️",
        bio: "実務経験はありません。Codexの扱いは得意です。",
        battleStats: ProfileBattleStats(battleCount: 42, firstPlaceCount: 18)
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
