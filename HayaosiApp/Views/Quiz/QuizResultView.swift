import SwiftUI

/// リザルト画面(練習)。要件 §5.4・§9-2
struct QuizResultView: View {
    let session: QuizSession
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("\(session.correctCount) / \(session.totalCount) 問正解")
                .font(.title.bold())

            if session.wrongCount > 0 {
                Text("間違えた\(session.wrongCount)問は復習リストに追加されました")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(Array(session.entries.enumerated()), id: \.offset) { _, entry in
                    resultRow(entry: entry)
                }
            }
            .listStyle(.insetGrouped)

            HStack(spacing: 16) {
                Button("もう一度") {
                    onRetry()
                }
                .buttonStyle(.bordered)

                Button("終了") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical)
        .navigationTitle("リザルト")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(entry: QuizSession.Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isCorrect ? "circle" : "xmark")
                .foregroundStyle(entry.isCorrect ? Color.green : Color.red)
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.question.text)
                    .font(.headline)
                Text("正解:\(entry.question.answer)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
