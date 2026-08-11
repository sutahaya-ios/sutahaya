import SwiftUI
import SwiftData

/// 一人練習の出題設定。要件 §5.3・§9-2
struct PracticeSetupView: View {
    @Query private var allQuestions: [Question]
    @State private var genre: Genre = .englishWord
    @State private var category = WordCategory.juniorHigh
    @State private var difficulty = WordDifficulty.one
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var quizQuestions: [Question] = []
    @State private var isPlaying = false

    var body: some View {
        Form {
            Section("出題設定") {
                Picker("ジャンル", selection: $genre) {
                    ForEach(Genre.allCases) { genre in
                        Text(genre.displayName).tag(genre)
                    }
                }
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
            }

            Section {
                Button("スタート") {
                    start()
                }
                .buttonStyle(SoundButtonStyle())
                .disabled(availableQuestions.isEmpty)
            } footer: {
                Text("\(category.displayName) \(difficulty.starDisplay)の収録問題数:\(availableQuestions.count)問")
            }
        }
        .navigationTitle("一人練習")
        .navigationDestination(isPresented: $isPlaying) {
            QuizSessionView(questions: quizQuestions, timeLimit: timeLimit, mode: .practice)
        }
    }

    private var availableQuestions: [Question] {
        allQuestions
            .filter { $0.genre == genre }
            .matching(category: category, difficulty: difficulty)
    }

    private func start() {
        quizQuestions = Array(availableQuestions.shuffled().prefix(questionCount))
        isPlaying = true
    }
}

#Preview {
    NavigationStack {
        PracticeSetupView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
