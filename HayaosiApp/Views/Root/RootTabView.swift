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

            // 設定はホーム右上へ移したので、ここは作問(次回アップデートで実装)
            NavigationStack { QuestionCreateView() }
                .tabItem { Label("作問", systemImage: "square.and.pencil") }
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
