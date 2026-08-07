import SwiftUI

/// お知らせが届くまで、空であることを明示する
struct NoticesView: View {
    var body: some View {
        ContentUnavailableView(
            "お知らせはありません",
            systemImage: "bell.slash",
            description: Text("新しいお知らせが届くと、ここに表示されます")
        )
        .navigationTitle("お知らせ")
    }
}

#Preview {
    NavigationStack {
        NoticesView()
    }
}
