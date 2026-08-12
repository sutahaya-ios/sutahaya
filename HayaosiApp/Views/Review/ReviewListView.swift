import SwiftUI
import SwiftData

/// 復習リスト。間違えた問題を一覧表示し、まとめて再出題する(要件 §5.3)
struct ReviewListView: View {
    private static let timeLimit: TimeInterval = 20

    let category: WordCategory?

    @Query(sort: \ReviewItem.wrongCount, order: .reverse) private var reviewItems: [ReviewItem]
    @Query private var allQuestions: [Question]
    @State private var quizQuestions: [Question] = []
    @State private var isPlaying = false

    init(category: WordCategory? = nil) {
        self.category = category
    }

    var body: some View {
        Group {
            if filteredReviewItems.isEmpty {
                ContentUnavailableView(
                    "復習する問題はありません",
                    systemImage: "checkmark.circle",
                    description: Text("練習で間違えた問題がここに登録されます")
                )
            } else {
                List {
                    Section {
                        ForEach(filteredReviewItems) { item in
                            reviewRow(item: item)
                        }
                    } footer: {
                        Text("正解できた問題は復習リストから自動で外れます")
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .safeAreaInset(edge: .bottom) {
            if !filteredReviewItems.isEmpty {
                Button("復習を始める(\(reviewQuestions.count)問)") {
                    start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .navigationDestination(isPresented: $isPlaying) {
            QuizSessionView(questions: quizQuestions, timeLimit: Self.timeLimit, mode: .practice)
        }
    }

    private var questionsByID: [String: Question] {
        Dictionary(uniqueKeysWithValues: allQuestions.map { ($0.id, $0) })
    }

    private var filteredReviewItems: [ReviewItem] {
        ReviewListFilter.filter(
            reviewItems: reviewItems,
            questions: allQuestions,
            category: category
        )
    }

    private var reviewQuestions: [Question] {
        filteredReviewItems.compactMap { questionsByID[$0.questionID] }
    }

    private var navigationTitle: String {
        guard let category else { return "復習リスト" }
        return "\(category.displayName)の復習"
    }

    private func reviewRow(item: ReviewItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(questionsByID[item.questionID]?.text ?? item.questionID)
                    .font(.headline)
                Text(questionsByID[item.questionID]?.answer ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.wrongCount)回ミス")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func start() {
        quizQuestions = reviewQuestions.shuffled()
        isPlaying = true
    }
}

#Preview {
    NavigationStack {
        ReviewListView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self, StudyTimeTotal.self], inMemory: true)
}
