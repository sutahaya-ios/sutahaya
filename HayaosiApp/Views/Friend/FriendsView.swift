import SwiftUI

/// マイページから開くフレンド一覧。追加・申請確認・削除もここで行う
/// Firebase未設定時はサンプルデータで同じUIを表示する(操作は無効)
struct FriendsView: View {
    /// Firebase未設定時のUI確認用サンプル
    private static let sampleFriends = [
        Friend(id: "sample-tokiya", nickname: "ときや", friendCode: "9GH2MN"),
        Friend(id: "sample-hanako", nickname: "はなこ", friendCode: "7PQ4RS")
    ]
    private static let sampleSentRequests = [
        SentFriendRequest(id: "sample-takeru", nickname: "たける", friendCode: "4AB8CD")
    ]
    private static let sampleReceivedRequests = [
        FriendRequest(id: "sample-sakura", nickname: "さくら", friendCode: "6EF2GH")
    ]

    @State private var selectedSection: FriendListSection = .friends
    @State private var showAddSheet = false
    @State private var showPreviewAlert = false
    @State private var signInFailed = false
    @State private var processingRequestIDs: Set<String> = []
    @State private var requestErrorMessage: String?
    @State private var friendPendingRemoval: Friend?

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        Group {
            if !OnlineService.isConfigured {
                friendContent(
                    friends: Self.sampleFriends,
                    sentRequests: Self.sampleSentRequests,
                    receivedRequests: Self.sampleReceivedRequests,
                    isPreview: true
                )
            } else if auth.uid != nil {
                friendContent(
                    friends: friendService.friends,
                    sentRequests: friendService.sentFriendRequests,
                    receivedRequests: friendService.friendRequests,
                    isPreview: false
                )
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
        .alert("フレンドを処理できませんでした", isPresented: requestErrorIsPresented) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(requestErrorMessage ?? "通信環境を確認して、もう一度お試しください")
        }
        .task(id: friendService.friends.map(\.id)) {
            guard OnlineService.isConfigured, auth.uid != nil else { return }
            await friendService.refreshFriendProfiles()
        }
        .confirmationDialog(
            "\(friendPendingRemoval?.nickname ?? "このフレンド")を削除しますか？",
            isPresented: removalConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("フレンドから削除", role: .destructive) {
                guard let friend = friendPendingRemoval else { return }
                remove(friend)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("相手のフレンド一覧からも削除されます")
        }
    }

    private func friendContent(
        friends: [Friend],
        sentRequests: [SentFriendRequest],
        receivedRequests: [FriendRequest],
        isPreview: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if isPreview {
                OnlinePreviewBanner()
                    .padding(.horizontal)
                    .padding(.top)
            }

            Picker("表示する一覧", selection: $selectedSection) {
                ForEach(FriendListSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("friend-list-tabs")

            ScrollView {
                selectedContent(
                    friends: friends,
                    sentRequests: sentRequests,
                    receivedRequests: receivedRequests,
                    isPreview: isPreview
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    @ViewBuilder
    private func selectedContent(
        friends: [Friend],
        sentRequests: [SentFriendRequest],
        receivedRequests: [FriendRequest],
        isPreview: Bool
    ) -> some View {
        switch selectedSection {
        case .friends:
            friendGrid(friends: friends, isPreview: isPreview)
        case .sent:
            sentRequestList(sentRequests)
        case .received:
            receivedRequestList(receivedRequests)
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
                                    friendPendingRemoval = friend
                                }
                            }
                        }
                }

                addTile(isPreview: isPreview)
            }

            Text("申請が承認されると双方のフレンド一覧へ表示されます。削除は長押しから。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sentRequestList(_ requests: [SentFriendRequest]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("送信済み(\(requests.count))")
                .font(.headline)

            if requests.isEmpty {
                requestEmptyState(
                    title: "送信済みの申請はありません",
                    message: "フレンドコードから申請すると、相手の名前がここに表示されます",
                    systemImage: "paperplane"
                )
            } else {
                ForEach(requests) { request in
                    SentFriendRequestRow(request: request)
                }
            }
        }
    }

    @ViewBuilder
    private func receivedRequestList(_ requests: [FriendRequest]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("受信中(\(requests.count))")
                .font(.headline)

            if requests.isEmpty {
                requestEmptyState(
                    title: "受信中の申請はありません",
                    message: "申請が届くと、相手の名前と承認ボタンがここに表示されます",
                    systemImage: "tray"
                )
            } else {
                ForEach(requests) { request in
                    FriendRequestRow(
                        request: request,
                        isWorking: processingRequestIDs.contains(request.id),
                        onAccept: { process(request, accept: true) },
                        onDecline: { process(request, accept: false) }
                    )
                }
            }
        }
    }

    private func requestEmptyState(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var requestErrorIsPresented: Binding<Bool> {
        Binding(
            get: { requestErrorMessage != nil },
            set: { if !$0 { requestErrorMessage = nil } }
        )
    }

    private var removalConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { friendPendingRemoval != nil },
            set: { if !$0 { friendPendingRemoval = nil } }
        )
    }

    private func process(_ request: FriendRequest, accept: Bool) {
        guard !processingRequestIDs.contains(request.id) else { return }
        processingRequestIDs.insert(request.id)
        Task {
            defer { processingRequestIDs.remove(request.id) }
            do {
                if accept {
                    try await friendService.acceptFriendRequest(request)
                } else {
                    try await friendService.declineFriendRequest(request)
                }
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ friend: Friend) {
        friendPendingRemoval = nil
        Task {
            do {
                try await friendService.removeFriend(id: friend.id)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
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

private enum FriendListSection: String, CaseIterable, Identifiable {
    case friends
    case sent
    case received

    var id: Self { self }

    var title: String {
        switch self {
        case .friends: "フレンド"
        case .sent: "送信済み"
        case .received: "受信中"
        }
    }
}

private struct SentFriendRequestRow: View {
    let request: SentFriendRequest

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(
                name: request.nickname,
                icon: ProfileIcon.none,
                size: 44,
                color: AvatarCircle.stableColor(for: request.id)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(request.nickname)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(request.friendCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("承認待ち")
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.nickname)、フレンドコード\(request.friendCode)、承認待ち")
    }
}

private struct FriendRequestRow: View {
    let request: FriendRequest
    let isWorking: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(
                name: request.nickname,
                icon: ProfileIcon.none,
                size: 44,
                color: AvatarCircle.stableColor(for: request.id)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(request.nickname)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(request.friendCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("拒否", role: .destructive, action: onDecline)
                .buttonStyle(.borderless)
            Button("承認", action: onAccept)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .disabled(isWorking)
        .opacity(isWorking ? 0.6 : 1)
    }
}

/// フレンド1人分のタイル(アバター・名前・コード)
private struct FriendTile: View {
    let friend: Friend

    var body: some View {
        VStack(spacing: 6) {
            AvatarCircle(
                name: friend.nickname,
                icon: friend.icon ?? ProfileIcon.none,
                size: 48,
                color: AvatarCircle.stableColor(for: friend.id)
            )
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
