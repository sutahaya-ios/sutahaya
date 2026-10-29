import SwiftUI
import SwiftData

/// 選択したレベル・形式の習得率を確認し、復習またはランダム練習へ進む
struct CategoryHeatmapView: View {
    private static let controlSpacing: CGFloat = 10
    private static let cornerRadius: CGFloat = 16
    private static let levelHeight: CGFloat = 48

    let category: StudyCategory

    @Query private var records: [AnswerRecord]
    @Query private var questions: [Question]
    @Query private var reviewItems: [ReviewItem]
    @State private var selectedDifficulty: StudyDifficulty = .one
    @State private var selectedFormat: QuestionFormat?
    @State private var quizQuestions: [Question] = []
    @State private var isPracticing = false
    @State private var sessionTimeLimit = QuizDefaults.timeLimit
    @AppStorage("studyPracticeQuestionCount") private var storedQuestionCount = QuizDefaults.questionCount
    @AppStorage private var storedTimeLimit: Double

    init(category: StudyCategory) {
        self.category = category
        // 教材ごとの時間を保持し、英単語とSPIの選択肢が混ざらないようにする。
        _storedTimeLimit = AppStorage(
            wrappedValue: category.defaultTimeLimit,
            "studyPracticeTimeLimit.\(category.rawValue)"
        )
    }

    var body: some View {
        let proficiency = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category,
            difficulty: selectedDifficulty,
            format: selectedFormat
        )
        let reviewItemCount = ReviewListFilter.filter(
            reviewItems: reviewItems,
            questions: questions,
            category: category
        ).count

        ScrollView {
            VStack(spacing: 24) {
                DifficultyProficiencyRing(
                    title: scopeTitle,
                    proficiencyRate: proficiency.progress
                )
                .padding(.vertical, 16)

                if !category.formats.isEmpty {
                    QuestionFormatSelector(formats: category.formats, selection: $selectedFormat)
                } else if usesDifficultyLevels {
                    difficultySelector
                }
                practiceActions(reviewItemCount: reviewItemCount)

                // 案内文が「他の難易度を選ぶ」ことを促すため、レベルを選べる教材だけに出す
                if usesDifficultyLevels && practiceQuestions.isEmpty {
                    QuestionAvailabilityNotice(
                        category: category,
                        difficulties: [selectedDifficulty]
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        // 画面に収まるときは動かさない。小さい端末で操作部がはみ出したときだけスクロールさせる
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isPracticing) {
            QuizSessionView(
                questions: quizQuestions,
                timeLimit: sessionTimeLimit,
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
        VStack(spacing: 18) {
            HStack {
                settingMenu(
                    "問題数",
                    values: QuizDefaults.questionCountOptions,
                    selection: Binding(get: { questionCount }, set: { storedQuestionCount = $0 }),
                    unit: "問"
                )
                Divider().frame(height: 40)
                settingMenu(
                    "1問の制限時間",
                    values: QuizDefaults.timeLimitOptions(for: category).map { Int($0) },
                    selection: Binding(get: { Int(timeLimit) }, set: { storedTimeLimit = Double($0) }),
                    unit: "秒"
                )
            }

            Button(action: startPractice) {
                Label("ランダム練習", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(.blue, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(practiceQuestions.isEmpty)
            .opacity(practiceQuestions.isEmpty ? 0.4 : 1)
            .accessibilityHint("\(scopeTitle)から最大\(questionCount)問、1問\(Int(timeLimit))秒で出題します")

            NavigationLink {
                ReviewListView(category: category)
            } label: {
                Label("復習 · 間違えた\(reviewItemCount)問", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: Self.cornerRadius)
        )
    }

    private func settingMenu(
        _ title: String,
        values: [Int],
        selection: Binding<Int>,
        unit: String
    ) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Picker(title, selection: selection) {
                    ForEach(values, id: \.self) { value in
                        Text("\(value)\(unit)").tag(value)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text("\(selection.wrappedValue)\(unit)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
            .accessibilityValue("\(selection.wrappedValue)\(unit)")
        }
        .frame(maxWidth: .infinity)
    }

    private var questionCount: Int {
        QuizDefaults.questionCountOptions.contains(storedQuestionCount)
            ? storedQuestionCount : QuizDefaults.questionCount
    }

    private var timeLimit: TimeInterval {
        QuizDefaults.timeLimitOptions(for: category).contains(storedTimeLimit)
            ? storedTimeLimit : category.defaultTimeLimit
    }

    private var usesDifficultyLevels: Bool {
        category.genre.usesDifficultyLevels
    }

    /// リングと読み上げに出す出題範囲の名前
    private var scopeTitle: String {
        if !category.formats.isEmpty {
            return selectedFormat?.displayName ?? "すべて"
        }
        return usesDifficultyLevels ? "レベル\(selectedDifficulty.rawValue)" : "全問"
    }

    private var practiceQuestions: [Question] {
        questions.matching(category: category, difficulty: selectedDifficulty, format: selectedFormat)
    }

    private func startPractice() {
        guard !practiceQuestions.isEmpty else { return }
        quizQuestions = Array(practiceQuestions.shuffled().prefix(questionCount))
        sessionTimeLimit = timeLimit
        isPracticing = true
    }
}

private struct DifficultyProficiencyRing: View {
    private static let diameter: CGFloat = 172
    private static let lineWidth: CGFloat = 10

    let title: String
    let proficiencyRate: Double

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
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
        .accessibilityLabel("\(title)、習得率\(rateText)")
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
