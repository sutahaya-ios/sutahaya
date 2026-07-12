import SwiftUI

/// フレンドタブ:マイコード表示・コードでフレンド追加・フレンド一覧
struct FriendsView: View {
    private static let friendCodeLength = 6

    @State private var codeInput = ""
    @State private var isWorking = false
    @State private var signInFailed = false
    @State private var errorMessage: String?

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        Group {
            if !OnlineService.isConfigured {
                OnlineSetupRequiredView()
            } else if auth.uid != nil {
                friendList
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
        .alert("エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var friendList: some View {
        List {
            Section {
                HStack {
                    Text(auth.friendCode ?? "------")
                        .font(.title.bold().monospaced())
                    Spacer()
                    Button {
                        UIPasteboard.general.string = auth.friendCode
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("マイコード")
            } footer: {
                Text("このコードを友達に伝えると、フレンドに追加してもらえます")
            }

            Section("フレンドを追加") {
                HStack {
                    TextField("フレンドコード(6桁)", text: $codeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("追加") {
                        Task { await addFriend() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(codeInput.count != Self.friendCodeLength || isWorking)
                }
            }

            Section {
                if friendService.friends.isEmpty {
                    Text("まだフレンドがいません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendService.friends) { friend in
                        HStack {
                            Label(friend.nickname, systemImage: "person.fill")
                            Spacer()
                            Text(friend.friendCode)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        Task { await removeFriends(at: indexSet) }
                    }
                }
            } header: {
                Text("フレンド(\(friendService.friends.count))")
            } footer: {
                Text("フレンドは片方向です(追加した相手が自分のリストに表示されます)")
            }
        }
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

    private func addFriend() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await friendService.addFriend(code: codeInput)
            codeInput = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFriends(at indexSet: IndexSet) async {
        for index in indexSet {
            guard friendService.friends.indices.contains(index) else { continue }
            await friendService.removeFriend(id: friendService.friends[index].id)
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
}
