import SwiftUI

/// 対戦結果と一人練習で共用する、問題・正解・解説のカード。
struct QuestionExplanationCard: View {
    enum UserAnswer {
        case selected(String)
        case timedOut
    }

    let question: Question
    let title: String
    var correctAnswer: String? = nil
    var userAnswer: UserAnswer? = nil

    private var answer: String { correctAnswer ?? question.answer }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(question.text)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let table = question.table {
                QuestionTableView(table: table)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("正解", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(answer)
                    .font(.title3.bold())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            if let userAnswer {
                userAnswerSection(userAnswer)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("解説", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(question.explanation)
                    .font(.body)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func userAnswerSection(_ userAnswer: UserAnswer) -> some View {
        let text: String
        let color: Color
        switch userAnswer {
        case .selected(let choice):
            text = choice
            color = choice == answer ? .green : .red
        case .timedOut:
            text = "時間切れ"
            color = .red
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("あなたの回答")
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.title3.bold())
                .textSelection(.enabled)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
