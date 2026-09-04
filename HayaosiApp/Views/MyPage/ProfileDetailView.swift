import SwiftUI
import SwiftData

/// プロフィールカードから開く詳細。区分ごとの戦績と、学習記録への入口をまとめる
struct ProfileDetailView: View {
    @Query private var battleRecords: [BattleRecord]
    @Query private var dailyStudyTimes: [DailyStudyTime]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(BattleMatchType.allCases) { matchType in
                    battleCard(for: matchType)
                }

                studyRecordCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func battleCard(for matchType: BattleMatchType) -> some View {
        let stats = BattleStatsSummary.calculate(records: battleRecords, matchType: matchType)

        return VStack(alignment: .leading, spacing: 14) {
            Text(matchType.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            BattleStatsRow(stats: stats)

            if stats.battleCount == 0 {
                Text("まだ記録がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var studyRecordCard: some View {
        NavigationLink {
            StudyRecordView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("学習記録")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(StudyDuration.text(seconds: totalStudySeconds))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var totalStudySeconds: Double {
        dailyStudyTimes.reduce(0) { $0 + max($1.totalSeconds, 0) }
    }
}

#Preview {
    NavigationStack {
        ProfileDetailView()
    }
    .modelContainer(
        for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self, BattleRecord.self],
        inMemory: true
    )
}
