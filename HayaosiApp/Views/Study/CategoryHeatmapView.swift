import SwiftUI
import SwiftData

/// 選択したレベルの習得率を確認し、復習またはランダム練習へ進む
struct CategoryHeatmapView: View {
    private static let controlSpacing: CGFloat = 10
    private static let cornerRadius: CGFloat = 16
    private static let levelHeight: CGFloat = 48
    private static let actionHeight: CGFloat = 112

    let category: StudyCategory

    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]
    @Query private var reviewItems: [ReviewItem]
    @State private var selectedDifficulty: StudyDifficulty = .one
    @State private var quizQuestions: [Question] = []
    @State private var isPracticing = false

    var body: some View {
        let proficiency = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category,
            difficulty: selectedDifficulty
        )
        let reviewItemCount = ReviewListFilter.filter(
            reviewItems: reviewItems,
            questions: questions,
            category: category
        ).count

        ScrollView {
            VStack(spacing: 24) {
                DifficultyProficiencyRing(
                    difficulty: selectedDifficulty,
                    proficiencyRate: proficiency.progress
                )
                .padding(.vertical, 16)

                difficultySelector
                practiceActions(reviewItemCount: reviewItemCount)

                if practiceQuestions.isEmpty {
                    QuestionAvailabilityNotice(
                        category: category,
                        difficulties: [selectedDifficulty]
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isPracticing) {
            QuizSessionView(
                questions: quizQuestions,
                timeLimit: QuizDefaults.timeLimit,
                mode: .practice
            )
        }
    }

    private var difficultySelector: some View {
        HStack(spacing: Self.controlSpacing) {
            ForEach(StudyDifficulty.allCases) { difficulty in
                let isSelected = selectedDifficulty == difficulty

                Button {
                    selectedDifficulty = difficulty
                } label: {
                    Text("\(difficulty.rawValue)")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Self.levelHeight)
                        .foregroundStyle(isSelected ? Color.blue : Color.primary)
                        .background(
                            isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: Self.cornerRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .strokeBorder(
                                    isSelected ? Color.blue : Color(.separator).opacity(0.3)
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("レベル\(difficulty.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func practiceActions(reviewItemCount: Int) -> some View {
        HStack(alignment: .top, spacing: Self.controlSpacing) {
            NavigationLink {
                ReviewListView(category: category)
            } label: {
                actionLabel(
                    "復習",
                    symbol: "arrow.counterclockwise",
                    detail: "間違えた\(reviewItemCount)問",
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)

            Button(action: startPractice) {
                actionLabel("ランダム練習", symbol: "shuffle", isPrimary: true)
            }
            .buttonStyle(.plain)
            .disabled(practiceQuestions.isEmpty)
            .opacity(practiceQuestions.isEmpty ? 0.4 : 1)
            .accessibilityHint("レベル\(selectedDifficulty.rawValue)からランダムに出題します")
        }
    }

    private func actionLabel(
        _ title: String,
        symbol: String,
        detail: String? = nil,
        isPrimary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isPrimary ? Color.white : Color.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPrimary ? Color.white : Color.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: Self.actionHeight, alignment: .topLeading)
        .background(
            isPrimary ? Color.blue : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: Self.cornerRadius)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    private var practiceQuestions: [Question] {
        questions.matching(category: category, difficulty: selectedDifficulty)
    }

    private func startPractice() {
        guard !practiceQuestions.isEmpty else { return }
        quizQuestions = Array(practiceQuestions.shuffled().prefix(QuizDefaults.questionCount))
        isPracticing = true
    }
}

private struct DifficultyProficiencyRing: View {
    private static let diameter: CGFloat = 172
    private static let lineWidth: CGFloat = 10

    let difficulty: StudyDifficulty
    let proficiencyRate: Double

    var body: some View {
        VStack(spacing: 20) {
            Text("レベル\(difficulty.rawValue)")
                .font(.title3.weight(.semibold))

            ZStack {
                Circle()
                    .stroke(Color(.secondarySystemBackground), lineWidth: Self.lineWidth)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.blue,
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 5) {
                    Text(rateText)
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text("習得率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(Self.lineWidth / 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("レベル\(difficulty.rawValue)、習得率\(rateText)")
    }

    private var progress: Double {
        min(max(proficiencyRate, 0), 1)
    }

    private var rateText: String {
        return "\(Int(progress * 100))%"
    }
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
