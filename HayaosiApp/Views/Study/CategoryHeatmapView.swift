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
    @Query private var reviewItems: [ReviewItem]

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
        let unavailableDifficulties = WordDifficulty.allCases.filter {
            practiceQuestions(for: $0).isEmpty
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("レベルをタップして練習を始める")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Self.difficultyColumns, spacing: 6) {
                    ForEach(WordDifficulty.allCases) { difficulty in
                        let matchingQuestions = practiceQuestions(for: difficulty)

                        if matchingQuestions.isEmpty {
                            DifficultyAccuracyCell(
                                difficulty: difficulty,
                                accuracy: proficiency.accuracy(for: difficulty),
                                isEnabled: false
                            )
                            .accessibilityLabel("\(difficulty.starDisplay)、問題なし")
                        } else {
                            NavigationLink {
                                QuizSessionView(
                                    questions: Array(
                                        matchingQuestions
                                            .shuffled()
                                            .prefix(QuizDefaults.questionCount)
                                    ),
                                    timeLimit: QuizDefaults.timeLimit,
                                    mode: .practice
                                )
                            } label: {
                                DifficultyAccuracyCell(
                                    difficulty: difficulty,
                                    accuracy: proficiency.accuracy(for: difficulty),
                                    isEnabled: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !unavailableDifficulties.isEmpty {
                    QuestionAvailabilityNotice(
                        category: category,
                        difficulties: unavailableDifficulties
                    )
                }

                Text("\(category.displayName)・難易度別正答率")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if reviewItemCount > 0 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)

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
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                }
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -2)
                }
            }
            .padding()
        }
        .navigationTitle(category.displayName)
    }

    private func practiceQuestions(for difficulty: WordDifficulty) -> [Question] {
        questions
            .filter { $0.genre == .englishWord }
            .matching(category: category, difficulty: difficulty)
    }
}

private struct DifficultyAccuracyCell: View {
    private static let ringDiameter: CGFloat = 56
    private static let ringLineWidth: CGFloat = 6

    private struct Style {
        let text: String
        let ringColor: Color
        let foregroundColor: Color
    }

    let difficulty: WordDifficulty
    let accuracy: Double?
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        Color(.secondarySystemBackground),
                        lineWidth: Self.ringLineWidth
                    )

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        style.ringColor,
                        style: StrokeStyle(
                            lineWidth: Self.ringLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))

                Text(style.text)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(style.foregroundColor)
            }
            .frame(width: Self.ringDiameter, height: Self.ringDiameter)

            Text("★\(difficulty.rawValue)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var progress: Double {
        min(max(accuracy ?? 0, 0), 1)
    }

    private var style: Style {
        guard let accuracy else {
            return Style(
                text: "－",
                ringColor: .clear,
                foregroundColor: .secondary
            )
        }

        let percentage = Int(accuracy * 100)
        if percentage >= 80 {
            return Style(
                text: "\(percentage)%",
                ringColor: .proficiencyGreen,
                foregroundColor: .proficiencyGreenText
            )
        }
        if percentage >= 55 {
            return Style(
                text: "\(percentage)%",
                ringColor: .proficiencyYellow,
                foregroundColor: .proficiencyYellowText
            )
        }
        return Style(
            text: "\(percentage)%",
            ringColor: .proficiencyRed,
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
        for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self],
        inMemory: true
    )
}
