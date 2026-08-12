import SwiftUI
import SwiftData

/// カテゴリ別の習得率・学習時間を要約し、難易度別学習へ案内する
struct CategorySummaryView: View {
    private static let metricColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    let category: WordCategory

    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]
    @Query private var reviewItems: [ReviewItem]
    @Query private var studyTimeTotals: [StudyTimeTotal]

    var body: some View {
        let proficiency = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category
        )
        let reviewItemCount = ReviewListFilter.filter(
            reviewItems: reviewItems,
            questions: questions,
            category: category
        ).count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Self.metricColumns, spacing: 10) {
                    CategoryMetricCard(label: "習得率", value: proficiencyText(for: proficiency))
                    CategoryMetricCard(label: "学習時間", value: studyTimeText)
                }

                Text(summaryDescription(for: proficiency))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                NavigationLink {
                    CategoryHeatmapView(category: category)
                } label: {
                    Text("学習")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                }
                .buttonStyle(.plain)

                if reviewItemCount > 0 {
                    NavigationLink {
                        ReviewListView(category: category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("復習リスト")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("間違えた問題 \(reviewItemCount)問")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(category.displayName)
    }

    private func proficiencyText(for proficiency: CategoryProficiencySummary) -> String {
        guard let rate = proficiency.proficiencyRate else { return "－" }
        return "\(Int(rate * 100))%"
    }

    private var studyTimeText: String {
        let storedSeconds = studyTimeTotals.first {
            $0.categoryRaw == category.rawValue
        }?.totalSeconds ?? 0
        let totalSeconds = max(storedSeconds, 0)
        let totalMinutes = Int(totalSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)分"
        }
        if minutes == 0 {
            return "\(hours)時間"
        }
        return "\(hours)時間\(minutes)分"
    }

    private func summaryDescription(for proficiency: CategoryProficiencySummary) -> String {
        guard proficiency.totalWordCount > 0 else {
            return "単語データがありません"
        }
        return "全\(proficiency.totalWordCount)語のうち\(proficiency.masteredWordCount)語を正解済み"
    }
}

private struct CategoryMetricCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    NavigationStack {
        CategorySummaryView(category: .juniorHigh)
    }
    .modelContainer(
        for: [Question.self, AnswerRecord.self, ReviewItem.self, StudyTimeTotal.self],
        inMemory: true
    )
}
