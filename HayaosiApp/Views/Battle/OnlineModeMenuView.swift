import SwiftUI

/// オンラインカードから、ルーム作成と参加のどちらへ進むかを選ぶ
struct OnlineModeMenuView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink {
                    RoomCreateView()
                } label: {
                    MenuCard(
                        title: "ルーム作成",
                        subtitle: "コードを発行して友達を招く",
                        systemImage: "plus.circle.fill",
                        color: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RoomJoinView()
                } label: {
                    MenuCard(
                        title: "ルーム参加",
                        subtitle: "コードを入力して入室する",
                        systemImage: "number.circle.fill",
                        color: .purple
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("オンライン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnlineModeMenuView()
    }
}
