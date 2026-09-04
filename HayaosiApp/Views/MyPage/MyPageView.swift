import SwiftUI
import SwiftData

/// マイページ。プロフィールを主役にし、友達・設定への入口をまとめる
struct MyPageView: View {
    @Query private var battleRecords: [BattleRecord]
    @AppStorage("nickname") private var nickname = "ゲスト"
    @AppStorage("profileIcon") private var profileIcon = ProfileIcon.none
    @AppStorage("profileBio") private var profileBio = ""
    @State private var signInFailed = false

    private var auth: AuthService { .shared }
    private var friendService: FriendService { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                profileSection

                NavigationLink {
                    FriendsView()
                } label: {
                    MyPageFriendsOverview(friends: friendService.friends)
                }
                .buttonStyle(.plain)

                settingsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("マイページ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(content: .profile)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                        Text("編集")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { AdBannerView() }
        .task {
            await prepareOnlineProfile()
        }
    }

    private var profileSection: some View {
        VStack(spacing: 10) {
            FriendProfileCard(
                nickname: nickname,
                friendCode: auth.friendCode,
                icon: profileIcon,
                bio: profileBio,
                battleStats: BattleStatsSummary.calculate(records: battleRecords)
            ) {
                ProfileDetailView()
            }

            onlineProfileStatus
        }
    }

    @ViewBuilder
    private var onlineProfileStatus: some View {
        if !OnlineService.isConfigured {
            Label("オンライン設定後にフレンドコードが発行されます", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if signInFailed {
            HStack(spacing: 10) {
                Label("プロフィールを読み込めませんでした", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("再試行") {
                    Task { await prepareOnlineProfile() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if auth.friendCode == nil {
            ProgressView("プロフィールを読み込み中…")
                .font(.caption)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("設定・その他", systemImage: "gearshape.fill")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                settingsLink(
                    title: "プレミアム(広告非表示)",
                    systemImage: "crown.fill",
                    destination: SubscriptionView()
                )

                Divider().padding(.leading, 52)

                settingsLink(
                    title: "サウンド・振動",
                    systemImage: "speaker.wave.2.fill",
                    destination: SettingsView(content: .soundAndHaptics)
                )

                Divider().padding(.leading, 52)

                settingsLink(
                    title: "学習データ",
                    systemImage: "book.fill",
                    destination: SettingsView(content: .learningData)
                )

                Divider().padding(.leading, 52)

                settingsLink(
                    title: "お知らせ",
                    systemImage: "bell.fill",
                    destination: NoticesView()
                )

                Divider().padding(.leading, 52)

                settingsLink(
                    title: "アプリ情報",
                    systemImage: "info.circle.fill",
                    destination: AppInformationView()
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }

    private func settingsLink<Destination: View>(
        title: String,
        systemImage: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func prepareOnlineProfile() async {
        guard OnlineService.isConfigured else { return }
        signInFailed = false

        if let uid = auth.uid {
            friendService.startListening(uid: uid)
            return
        }

        do {
            let uid = try await auth.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            guard !Task.isCancelled else { return }
            signInFailed = true
        }
    }
}

#Preview {
    NavigationStack {
        MyPageView()
    }
}
