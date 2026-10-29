import SwiftUI

struct AnswerFeedbackSymbol: View {
    private static let symbolSize: CGFloat = 100

    let isCorrect: Bool

    var body: some View {
        Image(systemName: isCorrect ? "circle" : "xmark")
            .font(.system(size: Self.symbolSize, weight: .bold))
            .foregroundStyle(isCorrect ? Color.green : Color.red)
            .accessibilityLabel(isCorrect ? "正解" : "不正解")
    }
}
