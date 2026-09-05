import SwiftUI

/// 起動直後に出すブランド画面。問題データの投入中もこれで覆う
struct SplashView: View {
    /// ロゴが浮き上がる時間
    private static let appearDuration = 0.45
    private static let markSize: CGFloat = 96

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                mark
                title
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.9)
        }
        .task {
            withAnimation(.easeOut(duration: Self.appearDuration)) { hasAppeared = true }
        }
    }

    private var mark: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: Self.markSize * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.markSize, height: Self.markSize)
            .background(Circle().fill(.tint))
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("スタはや")
                .font(.largeTitle.bold())
            Text("勉強系早押し対戦")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SplashView()
}
