import SwiftUI
import SwiftData

/// アプリのルート。主要機能をタブバーで切り替える
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("ホーム", systemImage: "house.fill") }

            NavigationStack { RoomHubView() }
                .tabItem { Label("ルーム", systemImage: "gamecontroller.fill") }

            NavigationStack { FriendsView() }
                .tabItem { Label("フレンド", systemImage: "person.2.fill") }

            NavigationStack { ReviewListView() }
                .tabItem { Label("復習", systemImage: "arrow.counterclockwise") }

            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .task {
            QuestionSeeder.seedIfNeeded(context: modelContext)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
