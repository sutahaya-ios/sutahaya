import SwiftUI
import SwiftData

/// マイページから開く学習記録。合計学習時間と、カテゴリごとの習得率・学習時間を見る。
/// ここは見るだけの画面で、練習の開始と復習リストは学習タブに置く
struct StudyRecordView: View {
    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]
    @Query private var dailyStudyTimes: [DailyStudyTime]

    /// 開いているカテゴリ。同時に開けるのは1つ
    @State private var expandedCategory: WordCategory?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                totalCard

                VStack(spacing: 10) {
                    ForEach(WordCategory.allCases) { category in
                        categoryCard(for: category)
                    }
                }

                Text("練習の開始と復習リストは学習タブにあります")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("学習記録")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("合計学習時間")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(StudyDuration.text(seconds: totalSummary.totalSeconds))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
            }

            StudyTimeBlock(summary: totalSummary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func categoryCard(for category: WordCategory) -> some View {
        let isExpanded = expandedCategory == category

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    expandedCategory = isExpanded ? nil : category
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(category.studyAccentColor)
                        .frame(width: 10, height: 10)

                    Text(category.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(StudyDuration.text(seconds: studyTime(for: category).totalSeconds))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(category.displayName)の学習記録")
            .accessibilityHint(isExpanded ? "閉じる" : "開く")

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    ProficiencyRingBlock(summary: proficiency(for: category))
                    StudyTimeBlock(summary: studyTime(for: category), showsTitle: false)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var totalSummary: StudyTimeHeatmap.Summary {
        StudyTimeHeatmap.calculate(records: dailyStudyTimes, category: nil)
    }

    private func studyTime(for category: WordCategory) -> StudyTimeHeatmap.Summary {
        StudyTimeHeatmap.calculate(records: dailyStudyTimes, category: category)
    }

    private func proficiency(for category: WordCategory) -> CategoryProficiencySummary {
        CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category
        )
    }
}

#Preview {
    NavigationStack {
        StudyRecordView()
    }
    .modelContainer(
        for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self],
        inMemory: true
    )
}
