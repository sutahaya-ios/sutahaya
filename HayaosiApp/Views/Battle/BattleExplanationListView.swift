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
                    // 解説なしの問題を除いた通し番号なので、元の出題番号とは区別する。
                    QuestionExplanationCard(
                        question: question,
                        title: "解説 \(index + 1)",
                        correctAnswer: correctAnswers[question.id]
                    )
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .tint(.blue)
        .navigationTitle("解説")
        .navigationBarTitleDisplayMode(.inline)
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
