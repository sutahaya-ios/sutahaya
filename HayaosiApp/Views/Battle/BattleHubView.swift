import SwiftUI
import SwiftData

/// 対戦タブ。オンライン作成・参加とCPU対戦をホームから直接始める。
struct BattleHubView: View {
    /// Firebase未設定でもオンライン区画の見た目を確認できるよう、招待を1件だけ表示する。
    private static let sampleInvite = RoomInvite(
        id: "sample",
        roomCode: "4821",
        fromNickname: "ときや"
    )

    @AppStorage("nickname") private var nickname = "ゲスト"
    @AppStorage("hasSeenBattleTutorial") private var hasSeenTutorial = false
    @AppStorage(OnlineRoomConfiguration.categoryKey)
    private var savedCategoryRaw = WordCategory.juniorHigh.rawValue
    @AppStorage(OnlineRoomConfiguration.difficultyKey)
    private var savedDifficultyValue = WordDifficulty.one.rawValue
    @AppStorage(OnlineRoomConfiguration.questionCountKey)
    private var savedQuestionCount = QuizDefaults.questionCount
    @AppStorage(OnlineRoomConfiguration.timeLimitKey)
    private var savedTimeLimit = QuizDefaults.timeLimit

    @Query private var allQuestions: [Question]
    @State private var onlineSession: OnlineBattleSession?
    @State private var cpuSession: CPUBattleSession?
    @State private var showOnlineRoom = false
    @State private var showCPURoom = false
    @State private var showCodeJoin = false
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showPreviewAlert = false
    @State private var isCreatingRoom = false
    @State private var isStartingCPU = false
    @State private var joiningInviteID: String?
    @State private var hiddenInviteIDs: Set<String> = []
    @State private var errorMessage: String?

    private var friendService: FriendService { .shared }

    private var isOnlineReady: Bool {
        OnlineService.isConfigured && OnlineService.isDatabaseAvailable
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnlineBattleHomeCard(
                    configuration: configuration,
                    isCreating: isCreatingRoom,
                    onCreate: createRoom,
                    onJoinByCode: { showCodeJoin = true },
                    onChangeSettings: { showSettings = true }
                )

                SoloBattleHomeCard(
                    isStarting: isStartingCPU,
                    onStart: startCPU
                )

                inviteBanners

                if !isOnlineReady {
                    OnlinePreviewBanner()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
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
        .navigationDestination(isPresented: $showOnlineRoom) {
            if let onlineSession {
                BattleFlowView(session: onlineSession)
            }
        }
        .navigationDestination(isPresented: $showCPURoom) {
            if let cpuSession {
                BattleFlowView(session: cpuSession)
            }
        }
        .navigationDestination(isPresented: $showCodeJoin) {
            RoomJoinView()
        }
        .navigationDestination(isPresented: $showSettings) {
            RoomCreateView(mode: .editPreferences)
        }
        .onChange(of: showOnlineRoom) { _, isShowing in
            if !isShowing {
                onlineSession?.leave()
                onlineSession = nil
            }
        }
        .onChange(of: showCPURoom) { _, isShowing in
            if !isShowing {
                cpuSession?.leave()
                cpuSession = nil
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

    @ViewBuilder
    private var inviteBanners: some View {
        ForEach(visibleInvites) { invite in
            RoomInviteBanner(
                invite: invite,
                memberCount: 1,
                isJoining: joiningInviteID == invite.id,
                onAccept: { accept(invite, isPreview: !isOnlineReady) },
                onDismiss: { dismiss(invite, isPreview: !isOnlineReady) }
            )
        }
    }

    private var configuration: OnlineRoomConfiguration {
        OnlineRoomConfiguration(
            category: WordCategory(rawValue: savedCategoryRaw) ?? .juniorHigh,
            difficulty: WordDifficulty(rawValue: savedDifficultyValue) ?? .one,
            questionCount: QuizDefaults.questionCountOptions.contains(savedQuestionCount)
                ? savedQuestionCount
                : QuizDefaults.questionCount,
            timeLimit: QuizDefaults.timeLimitOptions.contains(savedTimeLimit)
                ? savedTimeLimit
                : QuizDefaults.timeLimit
        )
    }

    private var availableQuestions: [Question] {
        allQuestions
            .filter { $0.genre == .englishWord }
            .matching(
                category: configuration.category,
                difficulty: configuration.difficulty
            )
    }

    private var visibleInvites: [RoomInvite] {
        let source = isOnlineReady ? friendService.invites : [Self.sampleInvite]
        return source.filter { !hiddenInviteIDs.contains($0.id) }
    }

    private func createRoom() {
        guard !isCreatingRoom, joiningInviteID == nil else { return }
        guard isOnlineReady else {
            showPreviewAlert = true
            return
        }
        guard !availableQuestions.isEmpty else {
            errorMessage = "この設定で出題できる問題がありません。「変更」から別の難易度を選んでください"
            return
        }

        isCreatingRoom = true
        Task {
            defer { isCreatingRoom = false }
            do {
                let uid = try await AuthService.shared.ensureSignedIn()
                let session = try OnlineBattleSession(myID: uid, nickname: nickname)
                try await session.createRoom(
                    settings: configuration.roomSettings(
                        availableQuestionCount: availableQuestions.count
                    )
                )
                onlineSession = session
                showOnlineRoom = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startCPU() {
        guard !isStartingCPU, !isCreatingRoom else { return }
        guard !availableQuestions.isEmpty else {
            errorMessage = "この設定で出題できる問題がありません。「変更」から別の難易度を選んでください"
            return
        }

        isStartingCPU = true
        cpuSession = CPUBattleSession(
            nickname: nickname,
            settings: configuration.roomSettings(
                availableQuestionCount: availableQuestions.count
            ),
            cpuCount: 2
        )
        showCPURoom = true
        isStartingCPU = false
    }

    private func accept(_ invite: RoomInvite, isPreview: Bool) {
        guard !isPreview else {
            showPreviewAlert = true
            return
        }
        guard joiningInviteID == nil, !isCreatingRoom else { return }

        joiningInviteID = invite.id
        Task {
            defer { joiningInviteID = nil }
            do {
                let uid = try await AuthService.shared.ensureSignedIn()
                let session = try OnlineBattleSession(myID: uid, nickname: nickname)
                try await session.joinRoom(code: invite.roomCode)
                onlineSession = session
                showOnlineRoom = true
                await friendService.deleteInvite(id: invite.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dismiss(_ invite: RoomInvite, isPreview: Bool) {
        guard !isPreview else {
            showPreviewAlert = true
            return
        }
        hiddenInviteIDs.insert(invite.id)
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
