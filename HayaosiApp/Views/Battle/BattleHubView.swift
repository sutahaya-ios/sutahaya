import SwiftUI
import SwiftData

/// 対戦タブ。全国対戦とフレンド対戦を同格の入口として表示する。
struct BattleHubView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @AppStorage("hasSeenBattleTutorial") private var hasSeenTutorial = false

    @State private var onlineSession: OnlineBattleSession?
    @State private var showOnlineRoom = false
    @State private var showOnlineMatch = false
    @State private var showFriendMenu = false
    @State private var showTutorial = false
    @State private var showPreviewAlert = false
    @State private var joiningInviteID: String?
    @State private var hiddenInviteIDs: Set<String> = []
    @State private var errorMessage: String?

    private var friendService: FriendService { .shared }

    private var isOnlineReady: Bool {
        OnlineService.isConfigured && OnlineService.isDatabaseAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("スタはや")
                .font(.headline.bold())
                .foregroundStyle(.primary.opacity(0.78))

            Spacer(minLength: 16)

            BattleHomeHero()

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if let invite = visibleToastInvite(at: timeline.date) {
                    InviteToastBanner(
                        invite: invite,
                        isJoining: joiningInviteID == invite.notificationID,
                        onAccept: { accept(invite, isPreview: !isOnlineReady) },
                        onDismiss: { dismissToast(invite) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.25), value: visibleToastNotificationID)
        }
        .safeAreaInset(edge: .bottom) { modeButtons }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { AdBannerView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
                .accessibilityLabel("遊び方")
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
        .navigationDestination(isPresented: $showOnlineMatch) {
            ContentUnavailableView {
                Label("オンライン対戦", systemImage: "globe")
            } description: {
                Text("全国のプレイヤーとの対戦は準備中です")
            }
            .navigationTitle("オンライン対戦")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showFriendMenu) {
            OnlineModeMenuView(
                invites: formalInvites,
                isOnlineReady: isOnlineReady,
                joiningInviteID: joiningInviteID,
                onAcceptInvite: { accept($0, isPreview: !isOnlineReady) }
            )
        }
        .navigationDestination(isPresented: $showOnlineRoom) {
            if let onlineSession {
                BattleFlowView(session: onlineSession)
            }
        }
        .onChange(of: showOnlineRoom) { _, isShowing in
            if !isShowing {
                onlineSession?.leave()
                onlineSession = nil
            }
        }
        .sheet(isPresented: $showTutorial, onDismiss: {
            hasSeenTutorial = true
        }) {
            BattleTutorialView()
        }
        .alert("オンライン機能が未設定です", isPresented: $showPreviewAlert) {
        } message: {
            Text("Firebase設定後にルーム作成・招待参加を利用できます(設定手順:FIREBASE_SETUP.md)")
        }
        .alert("エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// バナー広告と間隔を空けて画面下端に固定する主操作。
    private var modeButtons: some View {
        HStack(spacing: 12) {
            BattleModeButton(
                title: "オンライン対戦",
                subtitle: "全国のプレイヤーと対戦！",
                systemImage: "globe",
                action: { showOnlineMatch = true }
            )

            BattleModeButton(
                title: "フレンド対戦",
                subtitle: "友だちと対戦！",
                systemImage: "person.2.fill",
                action: { showFriendMenu = true }
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var inviteSource: [RoomInvite] {
        friendService.invites
    }

    private var formalInvites: [RoomInvite] {
        validInvites(at: .now)
    }

    private var visibleToastNotificationID: String? {
        visibleToastInvite(at: .now)?.notificationID
    }

    private func validInvites(at date: Date) -> [RoomInvite] {
        guard isOnlineReady else { return [] }
        return inviteSource.filter { invite in
            invite.isVisibleInvitation(at: date) && !isAlreadyInInvitedRoom(invite)
        }
    }

    private func visibleToastInvite(at date: Date) -> RoomInvite? {
        validInvites(at: date).first { !hiddenInviteIDs.contains($0.notificationID) }
    }

    private func isAlreadyInInvitedRoom(_ invite: RoomInvite) -> Bool {
        guard let myID = AuthService.shared.uid,
              let state = onlineSession?.state,
              state.roomInstanceID == invite.roomInstanceID else { return false }
        return state.players.contains { $0.id == myID }
    }

    private func accept(_ invite: RoomInvite, isPreview: Bool) {
        guard !isPreview else {
            showPreviewAlert = true
            return
        }
        guard joiningInviteID == nil else { return }

        joiningInviteID = invite.notificationID
        Task {
            defer { joiningInviteID = nil }
            do {
                let uid = try await AuthService.shared.ensureSignedIn()
                // claim取得前から6秒で打ち切り、10秒leaseに再招待可能な余白を残す。
                let joinDeadline = ContinuousClock.now.advanced(
                    by: RTDBJoinRetryPolicy.acceptOperationBudget
                )
                let claim = try await friendService.claimInvite(invite)
                let session = try OnlineBattleSession(myID: uid, nickname: nickname)
                do {
                    try await session.joinRoom(
                        code: invite.roomCode,
                        expectedRoomInstanceID: invite.roomInstanceID,
                        operationDeadline: joinDeadline
                    )
                    try await friendService.finalizeInvite(claim)
                } catch {
                    // RTDB参加後にclaimがstaleになった場合も、参加者だけを残さない。
                    if session.didCreatePlayerDuringLatestJoin {
                        session.leave()
                    }
                    do {
                        try await friendService.rollbackInvite(claim)
                    } catch let rollbackError as InviteLifecycleError
                        where rollbackError == .rollbackExpired {
                        // 期限後はpendingへ戻さず、logical expiredのまま扱う。
                    } catch {
                        print("招待claimのrollbackに失敗: \(error)")
                    }
                    throw error
                }
                onlineSession = session
                showOnlineRoom = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dismissToast(_ invite: RoomInvite) {
        withAnimation(.easeInOut(duration: 0.25)) {
            hiddenInviteIDs.formUnion([invite.notificationID])
        }
    }

    private func signIn() async {
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        BattleHubView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
