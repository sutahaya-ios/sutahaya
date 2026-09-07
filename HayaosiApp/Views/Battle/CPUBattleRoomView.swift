import SwiftUI

/// ローカルルームにだけNPC管理を足し、共通の対戦フローはそのまま再利用する。
struct CPUBattleRoomView: View {
    let session: CPUBattleSession

    @State private var showNPCManagement = false

    var body: some View {
        BattleFlowView(session: session)
            .toolbar {
                if session.isHost, session.state?.status == .waiting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showNPCManagement = true
                        } label: {
                            Label("NPC管理", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(SoundButtonStyle())
                    }
                }
            }
            .sheet(isPresented: $showNPCManagement) {
                NavigationStack {
                    NPCManagementView(session: session)
                }
                .presentationDetents([.medium, .large])
            }
    }
}
