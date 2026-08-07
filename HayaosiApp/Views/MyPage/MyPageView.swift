import SwiftUI

/// マイページ。プロフィール・友達・設定など、自分に関する入口を集約する
struct MyPageView: View {
    private static let privacyPolicyURLString = "https://saikyo-app-team.github.io/app-privacy/"

    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var signInFailed = false

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        List {
            Section {
                profileContent
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("つながり") {
                NavigationLink {
                    FriendsView()
                } label: {
                    Label("フレンド", systemImage: "person.2.fill")
                }
            }

            Section("アプリ") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("設定", systemImage: "gearshape.fill")
                }

                NavigationLink {
                    NoticesView()
                } label: {
                    Label("お知らせ", systemImage: "bell.fill")
                }

                NavigationLink {
                    QuestionCreateView()
                } label: {
                    Label("作問(次回アップデート予定)", systemImage: "square.and.pencil")
                }

                if let privacyPolicyURL = URL(string: Self.privacyPolicyURLString) {
                    Link(destination: privacyPolicyURL) {
                        Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                    }
                }
            }
        }
        .navigationTitle("マイページ")
        .task {
            await prepareOnlineProfile()
        }
    }

    private var profileContent: some View {
        VStack(spacing: 12) {
            FriendProfileCard(nickname: nickname, friendCode: auth.friendCode)

            if !OnlineService.isConfigured {
                Label("オンライン設定後にフレンドコードが発行されます", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if signInFailed {
                Label("プロフィールを読み込めませんでした", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if auth.friendCode == nil {
                ProgressView("プロフィールを読み込み中…")
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private func prepareOnlineProfile() async {
        guard OnlineService.isConfigured, auth.friendCode == nil else { return }
        do {
            let uid = try await auth.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            print("プロフィールの読み込みに失敗: \(error)")
            signInFailed = true
        }
    }
}

#Preview {
    NavigationStack {
        MyPageView()
    }
}
