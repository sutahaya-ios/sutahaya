import SwiftUI

/// ルームタブ:招待バナー(最上部)+ルーム作成・参加の2大カード(案A)
/// Firebase未設定時はサンプル招待で同じUIを表示する(操作は無効)
struct RoomHubView: View {
    /// Firebase未設定時のUI確認用サンプル
    private static let sampleInvite = RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや")

    @State private var showPreviewAlert = false
    @State private var inviteCode: String?
    @State private var showInviteJoin = false

    private var friendService: FriendService { .shared }

    private var isOnlineReady: Bool {
        OnlineService.isConfigured && OnlineService.isDatabaseAvailable
    }

    var body: some View {
        content(
            invites: isOnlineReady ? friendService.invites : [Self.sampleInvite],
            isPreview: !isOnlineReady
        )
        .navigationTitle("ルーム")
        .task {
            if isOnlineReady {
                await signIn()
            }
        }
        .navigationDestination(isPresented: $showInviteJoin) {
            RoomJoinView(initialCode: inviteCode ?? "")
        }
        .alert("オンライン機能が未設定です", isPresented: $showPreviewAlert) {
        } message: {
            Text("招待への参加はFirebase設定後に利用できます(設定手順:FIREBASE_SETUP.md)")
        }
    }

    private func content(invites: [RoomInvite], isPreview: Bool) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if isPreview {
                    OnlinePreviewBanner()
                }

                ForEach(invites) { invite in
                    InviteBanner(
                        invite: invite,
                        onAccept: {
                            if isPreview {
                                showPreviewAlert = true
                            } else {
                                accept(invite)
                            }
                        },
                        onDismiss: {
                            if isPreview {
                                showPreviewAlert = true
                            } else {
                                Task { await friendService.deleteInvite(id: invite.id) }
                            }
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

                NavigationLink {
                    BotBattleSetupView()
                } label: {
                    MenuCard(
                        title: "ボット対戦",
                        subtitle: "通信なしでボットと早押し練習",
                        systemImage: "cpu",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
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
