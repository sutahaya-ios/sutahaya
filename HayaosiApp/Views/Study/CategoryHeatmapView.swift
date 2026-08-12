import SwiftUI
import SwiftData

/// カテゴリ内の難易度別正答率を色分けし、選んだ条件で練習へ進める
struct CategoryHeatmapView: View {
    private static let difficultyColumns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: WordDifficulty.allCases.count
    )

    let category: WordCategory

    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]

    var body: some View {
        let proficiency = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("難易度をタップして練習を始める")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Self.difficultyColumns, spacing: 6) {
                    ForEach(WordDifficulty.allCases) { difficulty in
                        NavigationLink {
                            PracticeSetupView(
                                initialCategory: category,
                                initialDifficulty: difficulty
                            )
                        } label: {
                            DifficultyAccuracyCell(
                                difficulty: difficulty,
                                accuracy: proficiency.accuracy(for: difficulty)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("\(category.displayName)・難易度別正答率")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(category.displayName)
    }
}

private struct DifficultyAccuracyCell: View {
    private struct Style {
        let text: String
        let backgroundColor: Color
        let foregroundColor: Color
    }

    let difficulty: WordDifficulty
    let accuracy: Double?

    var body: some View {
        VStack(spacing: 0) {
            Text("★\(difficulty.rawValue)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            Text(style.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(style.foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(style.backgroundColor))
        }
        .frame(maxWidth: .infinity)
    }

    private var style: Style {
        guard let accuracy else {
            return Style(
                text: "－",
                backgroundColor: Color(.secondarySystemBackground),
                foregroundColor: .secondary
            )
        }

        let percentage = Int(accuracy * 100)
        if percentage >= 80 {
            return Style(
                text: "\(percentage)%",
                backgroundColor: .proficiencyGreen,
                foregroundColor: .proficiencyGreenText
            )
        }
        if percentage >= 55 {
            return Style(
                text: "\(percentage)%",
                backgroundColor: .proficiencyYellow,
                foregroundColor: .proficiencyYellowText
            )
        }
        return Style(
            text: "\(percentage)%",
            backgroundColor: .proficiencyRed,
            foregroundColor: .proficiencyRedText
        )
    }
}

private extension Color {
    static let proficiencyGreen = Color(
        red: 234.0 / 255.0,
        green: 243.0 / 255.0,
        blue: 222.0 / 255.0
    )
    static let proficiencyGreenText = Color(
        red: 39.0 / 255.0,
        green: 80.0 / 255.0,
        blue: 10.0 / 255.0
    )
    static let proficiencyYellow = Color(
        red: 250.0 / 255.0,
        green: 238.0 / 255.0,
        blue: 218.0 / 255.0
    )
    static let proficiencyYellowText = Color(
        red: 99.0 / 255.0,
        green: 56.0 / 255.0,
        blue: 6.0 / 255.0
    )
    static let proficiencyRed = Color(
        red: 252.0 / 255.0,
        green: 235.0 / 255.0,
        blue: 235.0 / 255.0
    )
    static let proficiencyRedText = Color(
        red: 121.0 / 255.0,
        green: 31.0 / 255.0,
        blue: 31.0 / 255.0
    )
}

#Preview {
    NavigationStack {
        CategoryHeatmapView(category: .juniorHigh)
    }
    .modelContainer(
        for: [Question.self, AnswerRecord.self, ReviewItem.self, StudyTimeTotal.self],
        inMemory: true
    )
}
