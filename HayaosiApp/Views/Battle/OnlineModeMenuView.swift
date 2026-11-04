import SwiftUI
import SwiftData

/// フレンド対戦の入口。既存のルーム機能・招待・ローカルNPC対戦を集約する。
struct OnlineModeMenuView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var onlineSession: OnlineBattleSession?
    @State private var cpuSession: CPUBattleSession?
    @State private var showOnlineRoom = false
    @State private var showCPURoom = false
    @State private var isCreatingOnlineRoom = false
    @State private var errorMessage: String?

    let invites: [RoomInvite]
    let isOnlineReady: Bool
    let joiningInviteID: String?
    let onAcceptInvite: (RoomInvite) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isOnlineReady {
                    OnlinePreviewBanner()
                }

                Button {
                    Task { await createOnlineRoom() }
                } label: {
                    MenuCard(
                        title: "ルーム作成",
                        subtitle: "コードを発行して友だちを招く",
                        systemImage: "plus.circle.fill",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())
                .disabled(isCreatingOnlineRoom)

                NavigationLink {
                    RoomJoinView()
                } label: {
                    MenuCard(
                        title: "コード参加",
                        subtitle: "ルームコードを入力する",
                        systemImage: "number.circle.fill",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())

                NavigationLink {
                    AuthoredBattleSetupView(isOnlineReady: isOnlineReady)
                } label: {
                    MenuCard(
                        title: "作問",
                        subtitle: "自分で作った問題集で対戦",
                        systemImage: "square.and.pencil",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())
                .accessibilityIdentifier("battle.authored")

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    inviteSection(at: timeline.date)
                }

                Button {
                    createCPURoom()
                } label: {
                    MenuCard(
                        title: "NPCと対戦",
                        subtitle: "ルームでNPCを追加してローカル対戦",
                        systemImage: "desktopcomputer",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("フレンド対戦")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showOnlineRoom) {
            if let onlineSession {
                BattleFlowView(session: onlineSession)
            }
        }
        .navigationDestination(isPresented: $showCPURoom) {
            if let cpuSession {
                CPUBattleRoomView(session: cpuSession)
            }
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
        .alert("エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func activeInvites(at date: Date) -> [RoomInvite] {
        invites.filter { invite in
            !isOnlineReady || invite.isVisibleInvitation(at: date)
        }
    }

    private func inviteSection(at date: Date) -> some View {
        let activeInvites = activeInvites(at: date)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Color.accentColor)
                Text("招待")
                    .font(.headline)
                Spacer()
                Text("\(activeInvites.count)件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if activeInvites.isEmpty {
                Text("届いている招待はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(activeInvites) { invite in
                    inviteRow(invite)
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func inviteRow(_ invite: RoomInvite) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(
                name: invite.fromNickname,
                icon: "",
                size: 44,
                color: .accentColor
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(invite.fromNickname)
                    .font(.subheadline.bold())
                Text("対戦に招待されています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                onAcceptInvite(invite)
            } label: {
                Group {
                    if joiningInviteID == invite.notificationID {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("参加")
                            .font(.subheadline.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(minWidth: 58, minHeight: 40)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(joiningInviteID != nil)
        }
    }

    private func createOnlineRoom() async {
        guard isOnlineReady else {
            errorMessage = "Firebase設定後にルーム作成を利用できます(設定手順:FIREBASE_SETUP.md)"
            return
        }
        guard let settings = savedRoomSettings() else { return }

        isCreatingOnlineRoom = true
        defer { isCreatingOnlineRoom = false }
        do {
            let uid = try await AuthService.shared.ensureAuthenticated()
            let newSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            try await newSession.createRoom(settings: settings)
            onlineSession = newSession
            showOnlineRoom = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createCPURoom() {
        guard let settings = savedRoomSettings() else { return }
        cpuSession = CPUBattleSession(
            nickname: nickname,
            settings: settings,
            cpuProfiles: []
        )
        showCPURoom = true
    }

    /// 設定画面を経由せず、保存済み設定(未保存なら既存既定値)からルーム設定を作る。
    private func savedRoomSettings() -> RoomState.Settings? {
        let configuration = OnlineRoomConfiguration()
        let availableQuestionCount = allQuestions
            .matching(
                category: configuration.category,
                difficulty: configuration.difficulty,
                format: configuration.format
            )
            .count
        guard availableQuestionCount > 0 else {
            errorMessage = "保存済みの条件に一致する問題がありません。対戦設定を変更してください。"
            return nil
        }
        return configuration.roomSettings(
            availableQuestionCount: availableQuestionCount
        )
    }
}

/// 作問フレンド対戦の問題集選択。共有から追加した問題集は意図的に除外する。
private struct AuthoredBattleSetupView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var service = QuestionSetService()
    @State private var session: OnlineBattleSession?
    @State private var showRoom = false
    @State private var creatingSetID: String?
    @State private var errorMessage: String?

    let isOnlineReady: Bool

    private var ownedSets: [QuestionSet] {
        service.library.filter { $0.creatorUID == service.uid }
    }

    var body: some View {
        List {
            Section {
                Text("フレンド対戦では、自分で作った問題集の○×・4択だけを使えます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if service.isLoading {
                Section { ProgressView("問題集を読み込み中…") }
            } else if let loadError = service.errorMessage {
                Section {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("再試行") { Task { await service.load() } }
                }
            } else {
                Section("自分の問題集") {
                    ForEach(ownedSets) { set in
                        let supportedCount = set.questions.filter(\.isSupportedInFriendBattle).count
                        Button {
                            Task { await createRoom(with: set) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(set.title).font(.headline).foregroundStyle(.primary)
                                    Text("対戦対応 \(supportedCount)問（○×・4択）")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if creatingSetID == set.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(creatingSetID != nil || supportedCount == 0)
                        .accessibilityIdentifier("battle.authoredSet.\(set.id)")
                    }

                    if ownedSets.isEmpty {
                        ContentUnavailableView(
                            "対戦できる問題集がありません",
                            systemImage: "square.and.pencil",
                            description: Text("学習タブの「作問」から、自分の問題集を作成してください。")
                        )
                    }
                }
            }
        }
        .navigationTitle("作問の問題集")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load() }
        .refreshable { await service.load() }
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                BattleFlowView(session: session)
            }
        }
        .onChange(of: showRoom) { _, isShowing in
            if !isShowing {
                session?.leave()
                session = nil
            }
        }
        .alert("ルームを作成できませんでした", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createRoom(with set: QuestionSet) async {
        guard isOnlineReady else {
            errorMessage = "Firebase設定後に作問対戦を利用できます。"
            return
        }
        let payloads = set.friendBattlePayloads
        guard !payloads.isEmpty else { return }

        creatingSetID = set.id
        defer { creatingSetID = nil }
        var newSession: OnlineBattleSession?
        do {
            let uid = try await AuthService.shared.ensureAuthenticated()
            let createdSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            newSession = createdSession
            let settings = RoomState.Settings(
                questionCount: payloads.count,
                timeLimit: 30,
                genre: .spi,
                questionSource: .authored,
                authoredQuestionSetID: set.id,
                authoredQuestionSetTitle: set.title
            )
            try await createdSession.createRoom(settings: settings)
            try await createdSession.prepareAuthoredQuestions(payloads)
            session = createdSession
            showRoom = true
        } catch {
            newSession?.leave()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        OnlineModeMenuView(
            invites: [RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや")],
            isOnlineReady: true,
            joiningInviteID: nil,
            onAcceptInvite: { _ in }
        )
    }
}
