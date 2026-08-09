import SwiftUI
import SwiftData

/// 待機ロビー:参加者一覧・設定確認・フレンド招待。ホストが開始する(要件 §9-4)
/// CPU対戦時は参加コード・招待などオンライン専用UIを出さない
struct BattleLobbyView: View {
    private static let inviteTitle = "マナビートで対戦しよう!"
    private static let roomCodeLabel = "ルームコード"
    private static let appStoreLabel = "アプリはこちら"
    private static let inviteShareButtonTitle = "招待リンクを共有"
    private static let inviteShareSystemImage = "square.and.arrow.up"
    private static let inviteLabelSeparator = ":"
    private static let inviteLineSeparator = "\n"

    let session: any BattleSession

    @Query private var allQuestions: [Question]
    @State private var invitedFriendIDs: Set<String> = []

    private var friendService: FriendService { .shared }

    var body: some View {
        List {
            if let state = session.state {
                Section {
                    if session.isOnline {
                        Text(state.code)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)

                        ShareLink(item: inviteMessage(roomCode: state.code)) {
                            Label(Self.inviteShareButtonTitle, systemImage: Self.inviteShareSystemImage)
                        }
                        .buttonStyle(.bordered)
                    }
                    LabeledContent("ジャンル", value: state.settings.genre.displayName)
                    if let category = state.settings.wordCategory,
                       let difficulty = state.settings.wordDifficulty {
                        LabeledContent("カテゴリ", value: category.displayName)
                        LabeledContent("難易度", value: difficulty.starDisplay)
                    } else {
                        LabeledContent("単語範囲", value: "すべて")
                    }
                    LabeledContent("問題数", value: "\(state.settings.questionCount)問")
                    LabeledContent("制限時間", value: "\(Int(state.settings.timeLimit))秒 / 問")
                } header: {
                    Text(session.isOnline ? "参加コード" : "対戦設定")
                } footer: {
                    Text(session.isOnline
                         ? "友達にこのコードを伝えて入室してもらいます"
                         : "通信なしのCPU対戦です")
                }

                Section("参加者(\(state.players.count)/\(BattleRules.maxPlayers))") {
                    ForEach(state.players) { player in
                        HStack {
                            Label(
                                player.nickname,
                                systemImage: player.id.hasPrefix("cpu-") ? "desktopcomputer" : "person.fill"
                            )
                            if player.id == state.hostID && session.isOnline {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                            if player.id == session.myID {
                                Text("(自分)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if session.isOnline && !friendService.friends.isEmpty {
                    inviteSection(roomCode: state.code)
                }

                startSection(state: state)
            }
        }
        .navigationTitle("待機ロビー")
    }

    private func inviteSection(roomCode: String) -> some View {
        Section("フレンドを招待") {
            ForEach(friendService.friends) { friend in
                HStack {
                    Text(friend.nickname)
                    Spacer()
                    if invitedFriendIDs.contains(friend.id) {
                        Label("招待済み", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("招待") {
                            invite(friend, roomCode: roomCode)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
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

    private func startSection(state: RoomState) -> some View {
        Section {
            if session.isHost {
                Button("対戦を開始") {
                    Task { await start(state: state) }
                }
                .disabled(state.players.count < BattleRules.minPlayersToStart)
            } else {
                Label("ホストの開始を待っています…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if session.isHost && state.players.count < BattleRules.minPlayersToStart {
                Text("対戦には\(BattleRules.minPlayersToStart)人以上の参加が必要です")
            }
        }
    }

    private func invite(_ friend: Friend, roomCode: String) {
        invitedFriendIDs.insert(friend.id)
        Task {
            do {
                try await friendService.sendInvite(to: friend.id, roomCode: roomCode)
            } catch {
                print("招待の送信に失敗: \(error)")
                invitedFriendIDs.remove(friend.id)
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
}
