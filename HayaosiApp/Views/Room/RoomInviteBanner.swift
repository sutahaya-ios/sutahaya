import SwiftUI

/// フレンドから届いたルーム招待をオンライン区画内に表示する
struct RoomInviteBanner: View {
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
            .accessibilityLabel("招待を閉じる")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }
}

#Preview {
    RoomInviteBanner(
        invite: RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや"),
        onAccept: {},
        onDismiss: {}
    )
    .padding()
}
