import SwiftUI

/// ルームタブ:ルーム作成・参加への導線と、フレンドからの招待一覧
struct RoomHubView: View {
    @State private var signInFailed = false
    @State private var inviteCode: String?
    @State private var showInviteJoin = false

    private var friendService: FriendService { .shared }

    var body: some View {
        Group {
            if !OnlineService.isConfigured {
                OnlineSetupRequiredView()
            } else if !OnlineService.isDatabaseAvailable {
                OnlineSetupRequiredView(databaseOnly: true)
            } else {
                content
            }
        }
        .navigationTitle("ルーム")
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink {
                    RoomCreateView()
                } label: {
                    MenuCard(
                        title: "ルーム作成",
                        subtitle: "コードを発行して友達を招く",
                        systemImage: "plus.circle.fill",
                        color: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RoomJoinView()
                } label: {
                    MenuCard(
                        title: "ルーム参加",
                        subtitle: "コードを入力して入室する",
                        systemImage: "number.circle.fill",
                        color: .purple
                    )
                }
                .buttonStyle(.plain)

                if !friendService.invites.isEmpty {
                    invitesSection
                }
            }
            .padding()
        }
        .task { await signIn() }
        .navigationDestination(isPresented: $showInviteJoin) {
            RoomJoinView(initialCode: inviteCode ?? "")
        }
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("届いている招待")
                .font(.headline)

            ForEach(friendService.invites) { invite in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(invite.fromNickname)から招待")
                            .font(.subheadline)
                        Text("ルーム \(invite.roomCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("参加") {
                        accept(invite)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Task { await friendService.deleteInvite(id: invite.id) }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accept(_ invite: RoomInvite) {
        inviteCode = invite.roomCode
        showInviteJoin = true
        Task { await friendService.deleteInvite(id: invite.id) }
    }

    private func signIn() async {
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            friendService.startListening(uid: uid)
        } catch {
            print("サインインに失敗: \(error)")
            signInFailed = true
        }
    }
}

#Preview {
    NavigationStack {
        RoomHubView()
    }
}
