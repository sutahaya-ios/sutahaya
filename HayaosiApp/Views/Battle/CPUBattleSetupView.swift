import SwiftUI
import SwiftData

/// CPU対戦の設定画面。Firebase不要でロビー→対戦→リザルトの流れを試せる
struct CPUBattleSetupView: View {
    private static let botCountRange = 1...(BattleRules.maxPlayers - 1)

    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var category = WordCategory.juniorHigh
    @State private var difficulty = WordDifficulty.one
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var cpuCount = 2
    @State private var session: CPUBattleSession?
    @State private var showRoom = false

    var body: some View {
        Form {
            Section("対戦設定") {
                LabeledContent("ジャンル", value: Genre.englishWord.displayName)
                WordClassificationPicker(category: $category, difficulty: $difficulty)
                Picker("問題数", selection: $questionCount) {
                    ForEach(QuizDefaults.questionCountOptions, id: \.self) { count in
                        Text("\(count)問").tag(count)
                    }
                }
                Picker("制限時間", selection: $timeLimit) {
                    ForEach(QuizDefaults.timeLimitOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))秒 / 問").tag(seconds)
                    }
                }
                Stepper("CPU \(cpuCount)体", value: $cpuCount, in: Self.botCountRange)
            }

            Section {
                Button("ロビーへ") {
                    start()
                }
                .buttonStyle(SoundButtonStyle())
                .disabled(availableQuestions.isEmpty)
            } footer: {
                Text("\(category.displayName) \(difficulty.starDisplay)の収録問題数:\(availableQuestions.count)問\n設定した問題数に満たない場合は、収録されている問題だけを出題します。")
            }
        }
        .navigationTitle("ひとりで(CPU対戦)")
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                BattleFlowView(session: session)
            }
        }
        .onChange(of: showRoom) { _, isShowing in
            if !isShowing {
                session?.leave()
                session = nil
            }
        }
    }

    private var availableQuestions: [Question] {
        allQuestions
            .filter { $0.genre == .englishWord }
            .matching(category: category, difficulty: difficulty)
    }

    private func start() {
        let availableQuestionCount = availableQuestions.count
        guard availableQuestionCount > 0 else { return }
        session = CPUBattleSession(
            nickname: nickname,
            settings: .init(
                questionCount: min(questionCount, availableQuestionCount),
                timeLimit: timeLimit,
                genre: .englishWord,
                wordCategory: category,
                wordDifficulty: difficulty
            ),
            cpuCount: cpuCount
        )
        showRoom = true
    }
}

#Preview {
    NavigationStack {
        CPUBattleSetupView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
