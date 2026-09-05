import SwiftUI

/// フレンド対戦の入口。既存のルーム機能・招待・ローカルNPC対戦を集約する。
struct OnlineModeMenuView: View {
    let invites: [RoomInvite]
    let isOnlineReady: Bool
    let joiningInviteID: String?
    let onAcceptInvite: (RoomInvite) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isOnlineReady {
                    OnlinePreviewBanner()
                }

                NavigationLink {
                    RoomCreateView()
                } label: {
                    MenuCard(
                        title: "ルーム作成",
                        subtitle: "コードを発行して友だちを招く",
                        systemImage: "plus.circle.fill",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())

                NavigationLink {
                    RoomJoinView()
                } label: {
                    MenuCard(
                        title: "コード参加",
                        subtitle: "ルームコードを入力する",
                        systemImage: "number.circle.fill",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    inviteSection(at: timeline.date)
                }

                NavigationLink {
                    CPUBattleSetupView()
                } label: {
                    MenuCard(
                        title: "NPCと対戦",
                        subtitle: "強さを選んでローカル対戦",
                        systemImage: "desktopcomputer",
                        color: .accentColor
                    )
                }
                .buttonStyle(SoundButtonStyle())
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("フレンド対戦")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func activeInvites(at date: Date) -> [RoomInvite] {
        invites.filter { invite in
            !isOnlineReady || invite.isVisibleInvitation(at: date)
        }
    }

    private func inviteSection(at date: Date) -> some View {
        let activeInvites = activeInvites(at: date)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Color.accentColor)
                Text("招待")
                    .font(.headline)
                Spacer()
                Text("\(activeInvites.count)件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if activeInvites.isEmpty {
                Text("届いている招待はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(activeInvites) { invite in
                    inviteRow(invite)
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func inviteRow(_ invite: RoomInvite) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(
                name: invite.fromNickname,
                icon: "",
                size: 44,
                color: .accentColor
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(invite.fromNickname)
                    .font(.subheadline.bold())
                Text("対戦に招待されています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                onAcceptInvite(invite)
            } label: {
                Group {
                    if joiningInviteID == invite.notificationID {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("参加")
                            .font(.subheadline.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(minWidth: 58, minHeight: 40)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(joiningInviteID != nil)
        }
    }
}

#Preview {
    NavigationStack {
        OnlineModeMenuView(
            invites: [RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや")],
            isOnlineReady: true,
            joiningInviteID: nil,
            onAcceptInvite: { _ in }
        )
    }
}
