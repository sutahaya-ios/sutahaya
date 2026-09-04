import SwiftUI
import SwiftData

/// 待機ロビー:参加者一覧・設定確認・フレンド招待。ホストが開始する(要件 §9-4)
/// CPU対戦時は参加コード・招待などオンライン専用UIを出さない
struct BattleLobbyView: View {
    private static let inviteTitle = "スタはやで対戦しよう!"
    private static let roomCodeLabel = "ルームコード"
    private static let appStoreLabel = "アプリはこちら"
    private static let inviteLabelSeparator = ":"
    private static let inviteLineSeparator = "\n"

    let session: any BattleSession
    let onLeave: () -> Void

    @Query private var allQuestions: [Question]
    @State private var inviteSentAtByFriendID: [String: Date] = [:]
    @State private var sendingInviteFriendIDs: Set<String> = []

    private var friendService: FriendService { .shared }

    var body: some View {
        ScrollView {
            if let state = session.state {
                VStack(spacing: 32) {
                    if session.isOnline {
                        roomCodeSection(state: state)
                    }
                    membersSection(state: state)
                    settingsCard(state: state)
                    if session.isOnline,
                       session.isHost,
                       state.roomInstanceID != nil,
                       !friendService.friends.isEmpty {
                        inviteCard(state: state)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 30)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("ルーム")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let state = session.state {
                startControl(state: state)
            }
        }
    }

    private func roomCodeSection(state: RoomState) -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Text("ルームID")
                    .font(.title3.weight(.semibold))
                Text(state.code)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                    .monospacedDigit()

                Spacer()

                ShareLink(item: inviteMessage(roomCode: state.code)) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }

            Divider()
        }
    }

    private func membersSection(state: RoomState) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("メンバー")
                    .font(.title3.bold())
                Spacer()
                HStack(spacing: 0) {
                    Text("\(state.players.count)")
                        .foregroundStyle(.blue)
                    Text("/\(BattleRules.maxPlayers)")
                }
            }
            .font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(state.players) { player in
                        playerCard(player, state: state)
                    }
                }
            }
        }
    }

    private func playerCard(_ player: RoomState.Player, state: RoomState) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                if player.id.hasPrefix("cpu-") {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.blue)
                } else {
                    Text(initials(for: player.nickname))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 76, height: 76)

            Text(player.nickname)
                .font(.body)
                .lineLimit(1)
                .frame(width: 82)

            if player.id == state.hostID && session.isOnline {
                Text("ホスト")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            } else if player.id == session.myID {
                Text("自分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func settingsCard(state: RoomState) -> some View {
        VStack(spacing: 24) {
            HStack {
                Text("対戦設定")
                    .font(.title3.bold())
                Spacer()
                if session.isHost {
                    Button(action: onLeave) {
                        HStack(spacing: 5) {
                            Text("変更")
                            Image(systemName: "chevron.right")
                        }
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("ルームを退出して設定画面へ戻ります")
                }
            }

            HStack(spacing: 0) {
                settingItem(
                    title: "ジャンル",
                    value: state.settings.wordCategory?.displayName ?? state.settings.genre.displayName,
                    systemImage: "book"
                )
                settingDivider
                settingItem(
                    title: "レベル",
                    value: compactDifficulty(state.settings.wordDifficulty),
                    systemImage: "star"
                )
                settingDivider
                settingItem(
                    title: "問題数",
                    value: "\(state.settings.questionCount)問",
                    systemImage: "list.bullet"
                )
                settingDivider
                settingItem(
                    title: "制限時間",
                    value: "\(Int(state.settings.timeLimit))秒",
                    systemImage: "clock"
                )
            }
            .padding(.vertical, 18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func settingItem(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 29, weight: .regular))
                .foregroundStyle(.blue)
                .frame(height: 32)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var settingDivider: some View {
        Divider()
            .frame(height: 106)
    }

    private func inviteCard(state: RoomState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("フレンドを招待")
                .font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(friendService.friends) { friend in
                        HStack {
                            Text(friend.nickname)
                            Spacer()
                            inviteControl(friend, state: state, now: timeline.date)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func inviteControl(_ friend: Friend, state: RoomState, now: Date) -> some View {
        if state.players.contains(where: { $0.id == friend.id }) {
            Label("参加中", systemImage: "person.fill.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if sendingInviteFriendIDs.contains(friend.id) {
            ProgressView()
        } else if let sentAt = inviteSentAtByFriendID[friend.id] {
            let remaining = sentAt.addingTimeInterval(RoomInvite.resendCooldown).timeIntervalSince(now)
            if remaining > 0 {
                Label("再招待まで\(Int(ceil(remaining)))秒", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("再招待") {
                    invite(friend, state: state)
                }
                .buttonStyle(.bordered)
            }
        } else {
            Button("招待") {
                invite(friend, state: state)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func startControl(state: RoomState) -> some View {
        VStack(spacing: 8) {
            if session.isHost {
                Button {
                    Task { await start(state: state) }
                } label: {
                    Text("対戦開始")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 17))
                        .contentShape(Rectangle())
                }
                .buttonStyle(LobbyPrimaryButtonStyle())
                .disabled(state.players.count < BattleRules.minPlayersToStart)

                if state.players.count < BattleRules.minPlayersToStart {
                    Text("対戦には\(BattleRules.minPlayersToStart)人以上の参加が必要です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("ホストの開始を待っています…", systemImage: "hourglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func inviteMessage(roomCode: String) -> String {
        var lines = [
            Self.inviteTitle,
            "\(Self.roomCodeLabel)\(Self.inviteLabelSeparator)\(roomCode)"
        ]
        if let appStoreURL = AppLinks.appStoreURL {
            lines.append("\(Self.appStoreLabel)\(Self.inviteLabelSeparator)\(appStoreURL.absoluteString)")
        }
        return lines.joined(separator: Self.inviteLineSeparator)
    }

    private func invite(_ friend: Friend, state: RoomState) {
        guard session.isHost,
              let roomInstanceID = state.roomInstanceID,
              sendingInviteFriendIDs.insert(friend.id).inserted else { return }
        Task {
            defer { sendingInviteFriendIDs.remove(friend.id) }
            do {
                let invite = try await friendService.sendInvite(
                    to: friend.id,
                    roomCode: state.code,
                    roomInstanceID: roomInstanceID
                )
                inviteSentAtByFriendID[friend.id] = invite.sentAt
            } catch let error as InviteLifecycleError {
                if case let .cooldown(until) = error {
                    inviteSentAtByFriendID[friend.id] = until.addingTimeInterval(
                        -RoomInvite.resendCooldown
                    )
                }
                print("招待の送信に失敗: \(error)")
            } catch {
                print("招待の送信に失敗: \(error)")
            }
        }
    }

    private func start(state: RoomState) async {
        let pool = allQuestions
            .filter { $0.genre == state.settings.genre }
            .matching(
                category: state.settings.wordCategory,
                difficulty: state.settings.wordDifficulty
            )
        let questions = Array(pool.shuffled().prefix(state.settings.questionCount))
        guard !questions.isEmpty else { return }
        await session.startGame(questions: questions)
    }

    private func initials(for nickname: String) -> String {
        let characters = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(characters.prefix(2)).uppercased()
    }

    private func compactDifficulty(_ difficulty: WordDifficulty?) -> String {
        difficulty.map { "★\($0.rawValue)" } ?? "—"
    }
}

private struct LobbyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                guard isPressed, !wasPressed else { return }
                SoundPlayer.shared.play(.button)
            }
    }
}
