import SwiftUI

/// リザルト画面(練習)。要件 §5.4・§9-2
struct QuizResultView: View {
    let session: QuizSession
    let onRetry: () -> Void
    let onClose: () -> Void

    @State private var selectedExplanation: ResultExplanation?

    private struct ResultExplanation: Identifiable {
        let id: Int
        let entry: QuizSession.Entry
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("\(session.correctCount) / \(session.totalCount) 問正解")
                .font(.title.bold())

            if session.wrongCount > 0 {
                Text("間違えた\(session.wrongCount)問は復習リストに追加されました")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if session.entries.contains(where: { !$0.question.explanation.isEmpty }) {
                Text("問題をタップすると解説を確認できます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(Array(session.entries.enumerated()), id: \.offset) { index, entry in
                    if entry.question.explanation.isEmpty {
                        resultRow(entry: entry)
                    } else {
                        Button {
                            selectedExplanation = ResultExplanation(id: index, entry: entry)
                        } label: {
                            resultRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .padding(.top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuizActionBar(
                secondaryTitle: "もう一度",
                secondarySystemImage: "arrow.counterclockwise",
                primaryTitle: "終了",
                onSecondary: onRetry,
                onPrimary: onClose
            )
        }
        .navigationTitle("リザルト")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedExplanation) { selection in
            QuizExplanationSheet(
                question: selection.entry.question,
                questionNumber: selection.id + 1,
                userAnswer: selection.entry.selectedChoice.map { .selected($0) } ?? .timedOut
            )
            .presentationDetents([.large])
        }
    }

    private func resultRow(entry: QuizSession.Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isCorrect ? "circle" : "xmark")
                .foregroundStyle(entry.isCorrect ? Color.green : Color.red)
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                if entry.question.genre.usesProgressiveReveal {
                    Text(entry.question.text)
                        .font(.headline)
                } else {
                    Text(QuestionPrompt(text: entry.question.text).body.replacingOccurrences(of: "\n", with: " ／ "))
                        .font(.headline)
                        .lineLimit(2)
                }
                answerSummary(entry: entry)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.question.explanation.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func answerSummary(entry: QuizSession.Entry) -> Text {
        let correct = Text("正解:\(entry.question.answer)").foregroundColor(.secondary)
        guard !entry.isCorrect else { return correct }
        return correct + Text("・あなた:\(entry.selectedChoice ?? "時間切れ")")
            .foregroundColor(.red)
    }
}
