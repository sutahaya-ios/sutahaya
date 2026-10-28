import SwiftUI

struct CompetitiveHomeView: View {
    let profile: CompetitiveProfileProjection?
    let isLoading: Bool
    let cooldownEndsAtEpochMS: Double?
    let serverTimeOffsetMS: Double
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                rankCard
                statsCard
                rulesCard
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = CompetitiveForfeitCooldownPolicy.remainingSeconds(
                    cooldownEndsAtEpochMS: cooldownEndsAtEpochMS,
                    clientNowEpochMS: context.date.timeIntervalSince1970 * 1_000,
                    serverTimeOffsetMS: serverTimeOffsetMS
                )
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(buttonTitle(remainingSeconds: remaining))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || remaining > 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationTitle("ランク戦")
        .background(Color(.systemGroupedBackground))
    }

    private func buttonTitle(remainingSeconds: Int) -> String {
        if remainingSeconds > 0 { return "再戦まで \(remainingSeconds)秒" }
        return isLoading ? "参加中…" : "対戦相手を探す"
    }

    private var rankCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 38))
                .foregroundStyle(.yellow)
            if let profile {
                Text(CompetitiveClientDisplay.tierName(profile.currentTier))
                    .font(.title.bold())
                if let progress = CompetitiveClientDisplay.rankProgress(for: profile) {
                    ProgressView(value: progress)
                        .tint(.blue)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("次のランクまでの進捗")
                        .accessibilityValue("\(Int((progress * 100).rounded()))パーセント")
                }
                if let rating = CompetitiveClientDisplay.ratingText(for: profile) {
                    Text(rating)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let remaining = CompetitiveClientDisplay.pointsToNextTierText(for: profile) {
                    Text(remaining)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("ランク情報を準備中")
                    .font(.title3.bold())
                Text("初回のQueue参加後にServerから取得します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat(
                title: "勝率",
                value: profile.map { CompetitiveClientDisplay.winRateText($0.stats.winRate) } ?? "—"
            )
            Divider().frame(height: 44)
            stat(title: "最高連勝", value: profile.map { "\($0.stats.maxWinStreak)" } ?? "—")
            Divider().frame(height: 44)
            stat(title: "累計勝利", value: profile.map { "\($0.stats.totalWins)" } ?? "—")
        }
        .padding(.vertical, 18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("4人・英単語・20問", systemImage: "person.3.fill")
                .font(.headline)
            Text("正解した順に20・10・5・1ポイント。誤答は−10ポイントです。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
