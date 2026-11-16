import SwiftUI

/// 対戦の問題文の枠。収まる問題は中央に置き、収まらない長い問題(SPIの文章題など)だけ縦スクロールさせる。
/// 早押しでは選択肢を常に見せたいので、画面全体ではなく問題文の枠だけを動かす
struct BattleQuestionScrollArea<Content: View>: View {
    private let content: Content

    /// 一度でも動かしたら「続きあり」の案内を消す
    @State private var hasScrolled = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            scrollingContent
        }
        .frame(maxHeight: .infinity)
    }

    private var scrollingContent: some View {
        ScrollView {
            content
                // 最後の行が下端のぼかしに隠れないよう、末尾に同じ高さの余白を足す
                .padding(.bottom, Metrics.fadeHeight)
        }
        // スクロール量ではなく指の動きで判定する。スクロールを妨げないよう同時認識にする
        .simultaneousGesture(
            DragGesture(minimumDistance: Metrics.scrolledThreshold)
                .onChanged { _ in hasScrolled = true }
        )
        .mask { fadeMask }
        .overlay(alignment: .bottom) {
            if !hasScrolled {
                continuationHint
            }
        }
        .animation(.easeOut(duration: Metrics.hintFadeDuration), value: hasScrolled)
    }

    /// 下端だけ透明へ落とし、続きがあることを見た目で伝える
    private var fadeMask: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.fadeHeight)
        }
    }

    private var continuationHint: some View {
        Label("続きあり", systemImage: "arrow.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
    }
}

/// ジェネリック型は保存型のstaticを持てないため、定数はファイル内の名前空間へ置く
private enum Metrics {
    static let fadeHeight: CGFloat = 32
    static let scrolledThreshold: CGFloat = 8
    static let hintFadeDuration: TimeInterval = 0.2
}

#Preview("収まらない問題") {
    BattleQuestionScrollArea {
        QuestionTextView(
            text: "文中の空欄に入る最も適切なものを1つ選べ。\n情報は細分化されていればいるほど使いやすい。その方が、情報を得るときにも、組み合わせるときにも扱いやすい。結果として情報は［　　］し、体系的な「知恵」ではなく、分裂した独立の「知識」のみが存在していくことになる。",
            mode: .full,
            isSingleWord: false,
            format: .fillBlank
        )
    }
    .frame(height: 160)
    .padding()
}

#Preview("収まる問題") {
    BattleQuestionScrollArea {
        QuestionTextView(
            text: "最初に示された二語の関係を考え、同じ関係の対になるように選べ。\n錠：鍵\nボルト：（　　）",
            mode: .full,
            isSingleWord: false,
            format: .twoWordRelation
        )
    }
    .frame(height: 260)
    .padding()
}
