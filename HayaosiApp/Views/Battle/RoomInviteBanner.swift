import SwiftUI

/// 対戦ホームの通常レイアウトを動かさず、一時的に重ねる招待通知。
struct InviteToastBanner: View {
    private static let displayDuration = Duration.seconds(10)
    private static let dismissThreshold: CGFloat = -24

    let invite: RoomInvite
    let isJoining: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(
                name: invite.fromNickname,
                icon: "",
                size: 46,
                color: .accentColor
            )

            Text("\(invite.fromNickname)から対戦招待")
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onAccept) {
                Group {
                    if isJoining {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("参加")
                            .font(.subheadline.bold())
                    }
                }
                .frame(minWidth: 58, minHeight: 40)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(isJoining)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(isJoining)
            .accessibilityLabel("招待通知を閉じる")
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 7)
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($dragOffset) { value, state, _ in
                    state = min(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height < Self.dismissThreshold {
                        onDismiss()
                    }
                }
        )
        .task(id: invite.notificationID) {
            do {
                try await Task.sleep(for: Self.displayDuration)
                onDismiss()
            } catch is CancellationError {
                // 表示対象が変わったときは、古い通知の自動Dismissを止める。
            } catch {
                print("招待通知の自動Dismiss待機に失敗: \(error)")
            }
        }
    }
}

#Preview {
    InviteToastBanner(
        invite: RoomInvite(id: "sample", roomCode: "4821", fromNickname: "ときや"),
        isJoining: false,
        onAccept: {},
        onDismiss: {}
    )
    .padding(8)
    .background(Color(.systemGroupedBackground))
}
