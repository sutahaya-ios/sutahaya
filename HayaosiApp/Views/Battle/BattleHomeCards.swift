import SwiftUI

/// 対戦ホームのオンライン操作と前回設定をまとめるカード。
struct OnlineBattleHomeCard: View {
    let configuration: OnlineRoomConfiguration
    let isCreating: Bool
    let onCreate: () -> Void
    let onJoinByCode: () -> Void
    let onChangeSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack(spacing: 12) {
                actionTile(
                    title: "ルーム作成",
                    subtitle: isCreating ? "作成中…" : "コードを発行",
                    systemImage: isCreating ? "ellipsis" : "plus.circle",
                    action: onCreate
                )
                .disabled(isCreating)

                actionTile(
                    title: "コード参加",
                    subtitle: "コードを入力",
                    systemImage: "number",
                    action: onJoinByCode
                )
                .disabled(isCreating)
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("デフォルト設定")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(settingsSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 4)

                Button(action: onChangeSettings) {
                    HStack(spacing: 4) {
                        Text("変更")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(SoundButtonStyle())
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.blue.opacity(0.09))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2.fill")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.blue))

            VStack(alignment: .leading, spacing: 4) {
                Text("オンラインで対戦")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("友達とコードを使って部屋を作成・参加")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.8))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(SoundButtonStyle())
    }

    private var settingsSummary: String {
        "\(configuration.category.displayName)・★\(configuration.difficulty.rawValue)・\(configuration.questionCount)問・\(Int(configuration.timeLimit))秒/問"
    }
}

/// 設定を挟まずCPUロビーへ進む、ひとり用のカード。
struct SoloBattleHomeCard: View {
    let isStarting: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "person.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.orange))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ひとりで対戦")
                        .font(.title2.bold())
                    Text("CPUと即座にバトル開始")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onStart) {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isStarting ? "準備中…" : "ひとりで始める")
                            .font(.headline)
                        Text("すぐにCPUと対戦")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 94)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(isStarting)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 18) {
            OnlineBattleHomeCard(
                configuration: .default,
                isCreating: false,
                onCreate: {},
                onJoinByCode: {},
                onChangeSettings: {}
            )
            SoloBattleHomeCard(isStarting: false, onStart: {})
        }
        .padding()
    }
}
