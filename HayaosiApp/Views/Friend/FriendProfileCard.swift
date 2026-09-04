import SwiftUI

/// 自分のプロフィールカード。プロフィールを主役にし、戦績とフレンドコードを1枚へまとめる。
/// ヘッダと戦績をタップすると `detailDestination` へ進む。
/// フレンドコード行をリンクの外に置いているのは、中のコピー・シェアボタンと
/// タップが競合しないようにするため
struct FriendProfileCard<Detail: View>: View {
    private static var copiedResetDelay: TimeInterval { 2 }

    let nickname: String
    let friendCode: String?
    var icon: String = ProfileIcon.none
    var bio: String = ""
    var battleStats: ProfileBattleStats
    @ViewBuilder var detailDestination: () -> Detail

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                detailDestination()
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    profileHeader
                    statsPanel
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("プロフィールの詳細を開く")

            friendCodePanel
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

    private var statsPanel: some View {
        HStack(spacing: 8) {
            BattleStatsRow(stats: battleStats)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(panelBackground)
    }

    private var friendCodePanel: some View {
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
        .padding(12)
        .background(panelBackground)
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

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground))
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
    NavigationStack {
        FriendProfileCard(
            nickname: "TOKIYA TEST DEMO",
            friendCode: "VH49YR",
            icon: "✏️",
            bio: "実務経験はありません。Codexの扱いは得意です。",
            battleStats: ProfileBattleStats(battleCount: 42, firstPlaceCount: 18)
        ) {
            Text("詳細")
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
