import SwiftUI
import SwiftData

/// アプリのルート。主要機能をタブバーで切り替える
struct RootTabView: View {
    private enum AppTab: Hashable {
        case battle
        case study
        case myPage
    }

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = AppTab.battle

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
        .task {
            QuestionSeeder.seedIfNeeded(context: modelContext)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self], inMemory: true)
}
