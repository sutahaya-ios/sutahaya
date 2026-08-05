import SwiftUI

/// 対戦画面の問題文表示。文字送り型では経過時間に応じて少しずつ見せる(要件 §5.1.2)
struct BattleQuestionText: View {
    /// 見せ方。誰かが押した後・正解発表中は全文を出す(回答者が読めないと答えられないため)
    enum Mode: Equatable {
        case progressing(startedAtMS: Double, timeLimit: TimeInterval)
        case full
    }

    private static let tickInterval: TimeInterval = 0.1
    private static let minimumHeight: CGFloat = 120

    let text: String
    let style: QuizStyle
    let mode: Mode

    var body: some View {
        Group {
            if style.revealsProgressively, case .progressing(let startedAtMS, let timeLimit) = mode {
                TimelineView(.periodic(from: .now, by: Self.tickInterval)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince1970 - startedAtMS / 1000
                    let count = ProgressiveReveal.visibleCount(
                        totalCharacters: text.count,
                        elapsed: elapsed,
                        timeLimit: timeLimit
                    )
                    questionText(String(text.prefix(count)), isComplete: count >= text.count)
                }
            } else {
                questionText(text, isComplete: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
    }

    /// 文字送り中は続きがあることを示すカーソルを付ける
    private func questionText(_ visible: String, isComplete: Bool) -> some View {
        (Text(visible) + Text(isComplete ? "" : "▍").foregroundColor(.secondary))
            .font(font)
            .multilineTextAlignment(.center)
    }

    /// 文字送り型の問題文(意味・説明文)は長いので小さめに出す
    private var font: Font {
        style.revealsProgressively
            ? .system(size: 24, weight: .semibold)
            : .system(size: 36, weight: .bold)
    }
}

#Preview("文字送り型") {
    BattleQuestionText(
        text: "その技術や習慣を、努力して自分のものにする",
        style: .progressive,
        mode: .progressing(startedAtMS: Date().timeIntervalSince1970 * 1000, timeLimit: 20)
    )
    .padding()
}

#Preview("速答型") {
    BattleQuestionText(text: "acquire", style: .speed, mode: .full)
        .padding()
}
