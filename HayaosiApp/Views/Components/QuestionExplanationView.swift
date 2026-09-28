import SwiftUI

/// 解答後に見せる解説。SPIは「なぜその答えになるか」が学習の本体なので、
/// 正誤表示より目立たせず、読みやすさを優先する
struct QuestionExplanationView: View {
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("解説", systemImage: "text.book.closed")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

#Preview {
    QuestionExplanationView(
        explanation: "売価は 800 + 160 = 960円。売価は定価の8割にあたるので、定価 = 960 ÷ 0.8 = 1200円。"
    )
    .padding()
}
