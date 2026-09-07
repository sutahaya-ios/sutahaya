import SwiftUI

/// 対戦画面の問題文。英単語は1文字ずつ出し(要件 §5.1.2)、SPIは最初から全文を見せる
struct BattleQuestionText: View {
    /// 見せ方。発表中と、文字送りしないジャンルでは全文を出す
    enum Mode: Equatable {
        case progressing(startedAtMS: Double)
        case full
    }

    private static let tickInterval: TimeInterval = 0.05
    private static let minimumHeight: CGFloat = 120

    let text: String
    let mode: Mode
    /// 単語は大きく等幅で、SPIの問題文は読みやすい本文サイズで出す
    var isSingleWord = true

    var body: some View {
        Group {
            if case .progressing(let startedAtMS) = mode {
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
            .font(isSingleWord
                  ? .system(size: 40, weight: .bold, design: .rounded)
                  : .system(.title3, weight: .semibold))
            .monospaced(isSingleWord)
            .multilineTextAlignment(isSingleWord ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: isSingleWord ? .center : .leading)
            .contentTransition(.identity)
    }
}

#Preview("文字送り中") {
    BattleQuestionText(
        text: "abandon",
        mode: .progressing(startedAtMS: Date().timeIntervalSince1970 * 1000)
    )
    .padding()
}

#Preview("正解発表") {
    BattleQuestionText(text: "abandon", mode: .full)
        .padding()
}

#Preview("SPI") {
    BattleQuestionText(
        text: "ある商品を1個800円で仕入れ、定価の2割引きで売ったところ、1個あたり160円の利益が出た。この商品の定価はいくらか。",
        mode: .full,
        isSingleWord: false
    )
    .padding()
}
