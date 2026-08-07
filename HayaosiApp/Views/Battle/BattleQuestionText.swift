import SwiftUI

/// 対戦画面の問題文(英単語)。文字送り型では1文字ずつ表示する(要件 §5.1.2)
struct BattleQuestionText: View {
    /// 見せ方。発表中や即答型では全文を出す
    enum Mode: Equatable {
        case progressing(startedAtMS: Double)
        case full
    }

    private static let tickInterval: TimeInterval = 0.05
    private static let minimumHeight: CGFloat = 120

    let text: String
    let style: QuizStyle
    let mode: Mode

    var body: some View {
        Group {
            if style.revealsProgressively, case .progressing(let startedAtMS) = mode {
                TimelineView(.periodic(from: .now, by: Self.tickInterval)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince1970 - startedAtMS / 1000
                    let count = ProgressiveReveal.visibleCount(totalCharacters: text.count, elapsed: elapsed)
                    questionText(String(text.prefix(count)), isComplete: count >= text.count)
                }
            } else {
                questionText(text, isComplete: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
    }

    /// 表示中はまだ続きがあることをカーソルで示す
    private func questionText(_ visible: String, isComplete: Bool) -> some View {
        (Text(visible) + Text(isComplete ? "" : "▍").foregroundColor(.secondary))
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospaced()
            .multilineTextAlignment(.center)
            .contentTransition(.identity)
    }
}

#Preview("文字送り中") {
    BattleQuestionText(
        text: "abandon",
        style: .progressiveChoice,
        mode: .progressing(startedAtMS: Date().timeIntervalSince1970 * 1000)
    )
    .padding()
}

#Preview("全文") {
    BattleQuestionText(text: "abandon", style: .speed, mode: .full)
        .padding()
}
