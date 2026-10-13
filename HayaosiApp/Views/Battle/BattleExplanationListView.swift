import SwiftUI

/// 対戦で出た問題の解説をまとめて振り返る。SPIは解き方を確認できて初めて学習になるため、
/// リザルトから開けるようにする
struct BattleExplanationListView: View {
    /// 出題順に並べた、解説を持つ問題
    let questions: [Question]
    let correctAnswers: [String: String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("\(questions.count)問の解説")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    explanationCard(question, index: index)
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .tint(.blue)
        .navigationTitle("解説")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func explanationCard(_ question: Question, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // 解説なしの問題を除いた通し番号なので、元の出題番号とは区別する。
            Text("解説 \(index + 1)")
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
                Text(correctAnswers[question.id] ?? question.answer)
                    .font(.title3.bold())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
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
}

#Preview {
    NavigationStack {
        BattleExplanationListView(
            questions: [
                Question(
                    id: "spi_n_0001",
                    genre: .spi,
                    type: .multipleChoice,
                    text: "ある商品を1個800円で仕入れ、定価の2割引きで売ったところ、1個あたり160円の利益が出た。この商品の定価はいくらか。",
                    choices: ["960円", "1000円", "1150円", "1200円", "1250円"],
                    answer: "1200円",
                    category: .spiNonVerbal,
                    difficulty: .three,
                    explanation: "売価は 800 + 160 = 960円。売価は定価の8割にあたるので、定価 = 960 ÷ 0.8 = 1200円。"
                )
            ],
            correctAnswers: [:]
        )
    }
}
