import SwiftUI

/// ルームタブ:招待バナー(最上部)+ルーム作成・参加の2大カード(案A)
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
                ForEach(friendService.invites) { invite in
                    InviteBanner(
                        invite: invite,
                        onAccept: { accept(invite) },
                        onDismiss: {
                            Task { await friendService.deleteInvite(id: invite.id) }
                        }
                    )
                }

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
            }
            .padding()
        }
        .task { await signIn() }
        .navigationDestination(isPresented: $showInviteJoin) {
            RoomJoinView(initialCode: inviteCode ?? "")
        }
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

/// フレンドからのルーム招待バナー
private struct InviteBanner: View {
    let invite: RoomInvite
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(invite.fromNickname)から招待")
                    .font(.subheadline.bold())
                Text("ルーム \(invite.roomCode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("参加", action: onAccept)
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }
}

#Preview {
    NavigationStack {
        RoomHubView()
    }
}
