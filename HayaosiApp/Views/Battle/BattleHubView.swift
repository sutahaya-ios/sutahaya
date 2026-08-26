import SwiftUI
import SwiftData

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
    @State private var showOnlineMenu = false
    @State private var showTutorial = false
    @AppStorage("hasSeenBattleTutorial") private var hasSeenTutorial = false

    private var friendService: FriendService { .shared }

    private var isOnlineReady: Bool {
        OnlineService.isConfigured && OnlineService.isDatabaseAvailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inviteBanners
                modeCards

                if !isOnlineReady {
                    OnlinePreviewBanner()
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTutorial = true
                } label: {
                    Label("遊び方", systemImage: "questionmark.circle")
                }
            }
        }
        .onAppear {
            if !hasSeenTutorial {
                showTutorial = true
            }
        }
        .task {
            if isOnlineReady {
                await signIn()
            }
        }
        .navigationDestination(isPresented: $showInviteJoin) {
            RoomJoinView(initialCode: inviteCode ?? "")
        }
        .navigationDestination(isPresented: $showOnlineMenu) {
            OnlineModeMenuView()
        }
        .sheet(isPresented: $showTutorial, onDismiss: {
            hasSeenTutorial = true
        }) {
            BattleTutorialView()
        }
        .alert("オンライン機能が未設定です", isPresented: $showPreviewAlert) {
        } message: {
            Text("招待への参加はFirebase設定後に利用できます(設定手順:FIREBASE_SETUP.md)")
        }
    }

    private var modeCards: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink {
                CPUBattleSetupView()
            } label: {
                BattleModeCard(
                    title: "ひとりで",
                    subtitle: "CPUと対戦\n通信なしですぐ遊べる",
                    systemImage: "person.fill",
                    color: .orange
                )
            }
            .buttonStyle(SoundButtonStyle())

            Button {
                showOnlineMenu = true
            } label: {
                BattleModeCard(
                    title: "オンライン",
                    subtitle: "友達と対戦\nルームを作成・参加",
                    systemImage: "person.2.fill",
                    color: .blue
                )
            }
            .buttonStyle(SoundButtonStyle())
        }
    }

    private var inviteBanners: some View {
        ForEach(isOnlineReady ? friendService.invites : [Self.sampleInvite]) { invite in
            RoomInviteBanner(
                invite: invite,
                onAccept: { accept(invite, isPreview: !isOnlineReady) },
                onDismiss: { dismiss(invite, isPreview: !isOnlineReady) }
            )
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
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
