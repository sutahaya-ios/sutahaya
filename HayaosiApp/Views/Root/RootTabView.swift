import SwiftUI
import SwiftData

/// アプリのルート。主要機能をタブバーで切り替える
struct RootTabView: View {
    private enum AppTab: Hashable {
        case battle
        case study
        case myPage
    }

    /// 一瞬で消えるちらつきを避けるため、スプラッシュは最低これだけ出す
    private static let minimumSplashDuration = Duration.milliseconds(700)
    private static let splashFadeDuration = 0.35

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = AppTab.battle
    @State private var isPreparing = true

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { BattleHubView() }
                .tabItem { Label("対戦", systemImage: "gamecontroller.fill") }
                .tag(AppTab.battle)

            NavigationStack { StudyHubView() }
                .tabItem { Label("学習", systemImage: "book.fill") }
                .tag(AppTab.study)

            NavigationStack { MyPageView() }
                .tabItem { Label("マイページ", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.myPage)
        }
        .overlay {
            if isPreparing {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task { await prepareQuestionData() }
    }

    /// 問題データの投入が終わるまでスプラッシュで覆う。
    /// 投入はメインスレッドを占有するため、覆っておかないと描きかけのタブバーが固まって見える
    private func prepareQuestionData() async {
        let startedAt = ContinuousClock.now
        QuestionSeeder.seedIfNeeded(context: modelContext)

        let remaining = Self.minimumSplashDuration - startedAt.duration(to: .now)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        withAnimation(.easeInOut(duration: Self.splashFadeDuration)) { isPreparing = false }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self], inMemory: true)
}
