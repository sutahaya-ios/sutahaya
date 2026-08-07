import SwiftUI

/// 対戦タブ。「誰と遊ぶか」を起点に、ひとり用とオンライン用の導線を分ける
struct BattleHubView: View {
    /// Firebase未設定でもオンライン区画の見た目を確認できるよう、招待を1件だけ表示する
    private static let sampleInvite = RoomInvite(
        id: "sample",
        roomCode: "4821",
        fromNickname: "ときや"
    )

    @State private var showPreviewAlert = false
    @State private var inviteCode: String?
    @State private var showInviteJoin = false

    private var friendService: FriendService { .shared }

    private var isOnlineReady: Bool {
        OnlineService.isConfigured && OnlineService.isDatabaseAvailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                soloSection
                onlineSection
            }
            .padding()
        }
        .navigationTitle("対戦")
        .task {
            if isOnlineReady {
                await signIn()
            }
        }
        .navigationDestination(isPresented: $showInviteJoin) {
            RoomJoinView(initialCode: inviteCode ?? "")
        }
        .alert("オンライン機能が未設定です", isPresented: $showPreviewAlert) {
        } message: {
            Text("招待への参加はFirebase設定後に利用できます(設定手順:FIREBASE_SETUP.md)")
        }
    }

    private var soloSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "ひとりで", subtitle: "好きなときにCPUと対戦")

            NavigationLink {
                BotBattleSetupView()
            } label: {
                MenuCard(
                    title: "ひとりで(CPU対戦)",
                    subtitle: "通信なしですぐに遊べます",
                    systemImage: "person.fill",
                    color: .orange
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "オンライン", subtitle: "友達とルームで対戦")

            if !isOnlineReady {
                OnlinePreviewBanner()
            }

            ForEach(isOnlineReady ? friendService.invites : [Self.sampleInvite]) { invite in
                RoomInviteBanner(
                    invite: invite,
                    onAccept: { accept(invite, isPreview: !isOnlineReady) },
                    onDismiss: { dismiss(invite, isPreview: !isOnlineReady) }
                )
            }

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
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func accept(_ invite: RoomInvite, isPreview: Bool) {
        guard !isPreview else {
            showPreviewAlert = true
            return
        }
        inviteCode = invite.roomCode
        showInviteJoin = true
        Task { await friendService.deleteInvite(id: invite.id) }
    }

    private func dismiss(_ invite: RoomInvite, isPreview: Bool) {
        guard !isPreview else {
            showPreviewAlert = true
            return
        }
        Task { await friendService.deleteInvite(id: invite.id) }
    }

    private func signIn() async {
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            print("サインインに失敗: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        BattleHubView()
    }
}
