import SwiftUI

/// マイページから開くフレンド一覧。追加・削除もここで行う
/// Firebase未設定時はサンプルデータで同じUIを表示する(操作は無効)
struct FriendsView: View {
    /// Firebase未設定時のUI確認用サンプル
    private static let sampleFriends = [
        Friend(id: "sample-tokiya", nickname: "ときや", friendCode: "9GH2MN"),
        Friend(id: "sample-hanako", nickname: "はなこ", friendCode: "7PQ4RS")
    ]
    @State private var showAddSheet = false
    @State private var showPreviewAlert = false
    @State private var signInFailed = false

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        Group {
            if !OnlineService.isConfigured {
                friendContent(friends: Self.sampleFriends, isPreview: true)
            } else if auth.uid != nil {
                friendContent(friends: friendService.friends, isPreview: false)
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
        .alert("オンライン機能が未設定です", isPresented: $showPreviewAlert) {
        } message: {
            Text("フレンドの追加・削除はFirebase設定後に利用できます(設定手順:FIREBASE_SETUP.md)")
        }
        .task(id: friendService.friends.map(\.id)) {
            guard OnlineService.isConfigured, auth.uid != nil else { return }
            await friendService.refreshFriendProfiles()
        }
    }

    private func friendContent(friends: [Friend], isPreview: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isPreview {
                    OnlinePreviewBanner()
                }

                friendGrid(friends: friends, isPreview: isPreview)
            }
            .padding()
        }
    }

    private func friendGrid(friends: [Friend], isPreview: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("フレンド(\(friends.count))")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(friends) { friend in
                    FriendTile(friend: friend)
                        .contextMenu {
                            Button("フレンドから削除", systemImage: "trash", role: .destructive) {
                                if isPreview {
                                    showPreviewAlert = true
                                } else {
                                    Task { await friendService.removeFriend(id: friend.id) }
                                }
                            }
                        }
                }

                addTile(isPreview: isPreview)
            }

            Text("フレンドは片方向です(追加した相手が自分のリストに表示されます)。削除は長押しから。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func addTile(isPreview: Bool) -> some View {
        Button {
            if isPreview {
                showPreviewAlert = true
            } else {
                showAddSheet = true
            }
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
            AvatarCircle(name: friend.nickname, icon: friend.icon ?? ProfileIcon.none, size: 48, color: AvatarCircle.stableColor(for: friend.id))
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
