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
            .filter { $0.genre == .englishWord }
            .matching(
                category: configuration.category,
                difficulty: configuration.difficulty
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
