import SwiftUI

/// マイページ内のフレンド概要。Presenceは持たず、取得済みのプロフィールだけを表示する
struct MyPageFriendsOverview: View {
    let friends: [Friend]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text("フレンド")
                    .font(.title3.bold())

                Spacer()

                Text("\(friends.count)人")
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(friends.prefix(3))) { friend in
                    friendSummary(friend)
                }

                addFriendSummary

                if friends.isEmpty {
                    Text("フレンドを追加すると、ここにプロフィールが表示されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .accessibilityHint("フレンド一覧を開きます")
    }

    private func friendSummary(_ friend: Friend) -> some View {
        VStack(spacing: 7) {
            AvatarCircle(
                name: friend.nickname,
                icon: friend.icon ?? ProfileIcon.none,
                size: 58,
                color: AvatarCircle.stableColor(for: friend.id)
            )

            Text(friend.nickname)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 62)
        }
    }

    private var addFriendSummary: some View {
        VStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                }

            Text("追加")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 62)
        }
    }
}

#Preview {
    MyPageFriendsOverview(
        friends: [
            Friend(id: "1", nickname: "たける", friendCode: "ABC123", icon: "🐶"),
            Friend(id: "2", nickname: "SATO", friendCode: "DEF456", icon: "🐱"),
            Friend(id: "3", nickname: "YUI", friendCode: "GHI789", icon: "🐼")
        ]
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
