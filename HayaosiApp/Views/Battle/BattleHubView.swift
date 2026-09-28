import SwiftUI
import SwiftData

/// 対戦タブ。全国対戦とフレンド対戦を同格の入口として表示する。
struct BattleHubView: View {
    private static let nameMaxLength = 12
    private static let defaultNickname = "ゲスト"

    @AppStorage("nickname") private var nickname = defaultNickname
    @AppStorage("profileIcon") private var profileIcon = ProfileIcon.none
    @AppStorage("profileBio") private var profileBio = ""
    @AppStorage("hasSeenBattleTutorial") private var hasSeenTutorial = false
    @AppStorage(OnlineRoomConfiguration.categoryKey)
    private var savedCategoryRaw = StudyCategory.juniorHigh.rawValue
    @AppStorage(OnlineRoomConfiguration.difficultyKey)
    private var savedDifficultyValue = StudyDifficulty.one.rawValue
    @AppStorage(OnlineRoomConfiguration.questionCountKey)
    private var savedQuestionCount = QuizDefaults.questionCount
    @AppStorage(OnlineRoomConfiguration.timeLimitKey)
    private var savedTimeLimit = QuizDefaults.timeLimit

    @Query private var allQuestions: [Question]
    @Query private var answerRecords: [AnswerRecord]

    @FocusState private var isNameFieldFocused: Bool
    @State private var isEditingName = false
    @State private var nameDraft = ""

    @State private var onlineSession: OnlineBattleSession?
    @State private var showOnlineRoom = false
    @State private var showFriendMenu = false
    @State private var showSettings = false
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
            BattleScopeCard(
                categoryName: configuration.category.displayName,
                difficulty: configuration.difficulty.rawValue,
                proficiency: proficiency
            )

            settingsBand

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
            ToolbarItem(placement: .topBarLeading) {
                profileBar
            }

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
        .navigationDestination(isPresented: $showSettings) {
            RoomCreateView(mode: .editPreferences)
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

    /// 左上のプロフィール。アイコンで対戦実績を開き、名前はその場で編集する。
    private var profileBar: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ProfileDetailView()
            } label: {
                AvatarCircle(name: nickname, icon: profileIcon, size: 32, color: .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("対戦実績を見る")

            if isEditingName {
                nameField
            } else {
                nameButton
            }
        }
    }

    /// キーボードの確定キーで保存する。フォーカスが外れた時も同じ扱いにして、
    /// 編集したまま画面に残らないようにする
    private var nameField: some View {
        TextField("名前", text: $nameDraft)
            .font(.headline)
            .frame(minWidth: 120, maxWidth: 170)
            .focused($isNameFieldFocused)
            .task { isNameFieldFocused = true }
            .submitLabel(.done)
            .onSubmit(commitName)
            .onChange(of: nameDraft) { _, newDraft in
                if newDraft.count > Self.nameMaxLength {
                    nameDraft = String(newDraft.prefix(Self.nameMaxLength))
                }
            }
            .onChange(of: isNameFieldFocused) { _, isFocused in
                if !isFocused {
                    commitName()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
    }

    private var nameButton: some View {
        Button(action: beginNameEdit) {
            HStack(spacing: 5) {
                Text(hasNickname ? nickname : "名前を決める")
                    .font(.headline)
                    .foregroundStyle(hasNickname ? Color.primary : Color.accentColor)
                    .lineLimit(1)

                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            // ツールバー内では幅が詰められ、名前が消えてしまうため固有幅を保つ
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("名前を変更")
    }

    /// 初期値のままなら未設定として扱い、名前を決める導線を出す
    private var hasNickname: Bool {
        !nickname.isEmpty && nickname != Self.defaultNickname
    }

    private func beginNameEdit() {
        nameDraft = hasNickname ? nickname : ""
        isEditingName = true
    }

    /// 空欄なら既定の「ゲスト」へ戻す(相手のロビーで名無しにしないため)。
    /// 確定時にオンラインプロフィールへも反映する
    private func commitName() {
        guard isEditingName else { return }

        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        nickname = trimmed.isEmpty ? Self.defaultNickname : String(trimmed.prefix(Self.nameMaxLength))
        isEditingName = false
        isNameFieldFocused = false

        let latestNickname = nickname
        let latestIcon = profileIcon
        let latestBio = profileBio
        Task {
            await AuthService.shared.updateProfileIfSignedIn(
                nickname: latestNickname,
                icon: latestIcon,
                bio: latestBio
            )
        }
    }

    /// 出題範囲の下に置く、静かな設定行。
    private var settingsBand: some View {
        HStack(spacing: 8) {
            Text("\(configuration.questionCount)問・\(Int(configuration.timeLimit))秒 / 問")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                HStack(spacing: 3) {
                    Text("変更")
                        .font(.subheadline.bold())
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(SoundButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }

    private var configuration: OnlineRoomConfiguration {
        let category = StudyCategory(rawValue: savedCategoryRaw) ?? .juniorHigh
        return OnlineRoomConfiguration(
            genre: category.genre,
            category: category,
            difficulty: StudyDifficulty(rawValue: savedDifficultyValue) ?? .one,
            questionCount: QuizDefaults.questionCountOptions.contains(savedQuestionCount)
                ? savedQuestionCount
                : QuizDefaults.questionCount,
            timeLimit: QuizDefaults.timeLimitOptions(for: category).contains(savedTimeLimit)
                ? savedTimeLimit
                : category.defaultTimeLimit
        )
    }

    /// 学習記録と同じ集計を、選択中のカテゴリと難易度に絞って使う。
    /// 対戦設定を変えると、この値も切り替わる
    private var proficiency: CategoryProficiencySummary {
        CategoryProficiencySummary.calculate(
            records: answerRecords,
            questions: allQuestions,
            category: configuration.category,
            difficulty: configuration.difficulty
        )
    }

    /// バナー広告と間隔を空けて画面下端に固定する主操作。
    private var modeButtons: some View {
        HStack(spacing: 12) {
            BattleModeButton(
                title: "オンライン対戦",
                systemImage: "globe",
                isEnabled: false,
                action: {}
            )

            BattleModeButton(
                title: "フレンド対戦",
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
                        OnlineService.debugLog("招待claimのrollbackに失敗: \(error)")
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
