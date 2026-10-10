import SwiftUI

/// 起動直後に出すブランド画面。問題データの投入中もこれで覆う。
/// アプリアイコンと地続きに見せるため、配色はライト・ダーク共通で固定している
struct SplashView: View {
    /// マークが浮き上がる時間
    private static let appearDuration = 0.3
    private static let pencilHeight: CGFloat = 120

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color(.splashBackground)
                .ignoresSafeArea()

            Image(.splashPencil)
                .resizable()
                .scaledToFit()
                .frame(height: Self.pencilHeight)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.92)
                .accessibilityLabel("スタはや")
        }
        .task {
            withAnimation(.easeOut(duration: Self.appearDuration)) { hasAppeared = true }
        }
    }
}

#Preview {
    SplashView()
}
