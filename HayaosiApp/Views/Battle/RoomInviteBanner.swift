import SwiftUI

/// フレンドから届いたルーム招待を、見逃さないよう対戦タブ上部に表示する
struct RoomInviteBanner: View {
    let invite: RoomInvite
    let memberCount: Int
    let isJoining: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("対戦招待")
                    .font(.title3.bold())
                Spacer()
                Text("たった今")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                AvatarCircle(
                    name: invite.fromNickname,
                    icon: "",
                    size: 58,
                    color: .blue
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(invite.fromNickname)さん")
                        .font(.headline)
                        .lineLimit(1)
                    Text("一緒にバトルしよう！")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ルームメンバー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(memberCount)/\(BattleRules.maxPlayers)")
                        .font(.headline)
                }
            }

            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Group {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("参加する")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 15))
                .disabled(isJoining)

                Button("あとで", action: onDismiss)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 15))
                    .disabled(isJoining)
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 7)
    }
}

#Preview {
    RoomInviteBanner(
        invite: RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや"),
        memberCount: 1,
        isJoining: false,
        onAccept: {},
        onDismiss: {}
    )
    .padding()
}
