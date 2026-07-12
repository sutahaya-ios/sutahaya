import SwiftUI

/// フレンドタブ:プロフィールカード+フレンドのアバターグリッド(案B)
struct FriendsView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var showAddSheet = false
    @State private var signInFailed = false

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        Group {
            if !OnlineService.isConfigured {
                OnlineSetupRequiredView()
            } else if auth.uid != nil {
                content
            } else if signInFailed {
                ContentUnavailableView {
                    Label("サインインできません", systemImage: "wifi.slash")
                } description: {
                    Text("通信環境を確認して、もう一度開いてください")
                }
            } else {
                ProgressView("サインイン中…")
                    .task { await signIn() }
            }
        }
        .navigationTitle("フレンド")
        .sheet(isPresented: $showAddSheet) {
            AddFriendSheet()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FriendProfileCard(nickname: nickname, friendCode: auth.friendCode ?? "------")

                friendGrid
            }
            .padding()
        }
    }

    private var friendGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("フレンド(\(friendService.friends.count))")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(friendService.friends) { friend in
                    FriendTile(friend: friend)
                        .contextMenu {
                            Button("フレンドから削除", systemImage: "trash", role: .destructive) {
                                Task { await friendService.removeFriend(id: friend.id) }
                            }
                        }
                }

                addTile
            }

            Text("フレンドは片方向です(追加した相手が自分のリストに表示されます)。削除は長押しから。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var addTile: some View {
        Button {
            showAddSheet = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.secondary)
                    )
                Text("追加")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text("コード入力")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(.quaternary)
            )
        }
        .buttonStyle(.plain)
    }

    private func signIn() async {
        do {
            let uid = try await auth.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            print("サインインに失敗: \(error)")
            signInFailed = true
        }
    }
}

/// フレンド1人分のタイル(アバター・名前・コード)
private struct FriendTile: View {
    let friend: Friend

    var body: some View {
        VStack(spacing: 6) {
            AvatarCircle(name: friend.nickname, size: 48, color: AvatarCircle.stableColor(for: friend.id))
            Text(friend.nickname)
                .font(.caption)
                .lineLimit(1)
            Text(friend.friendCode)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
}
