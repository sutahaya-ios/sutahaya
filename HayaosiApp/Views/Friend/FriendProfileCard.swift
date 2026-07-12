import SwiftUI

/// 自分の「会員証」風カード:アバター・ニックネーム・フレンドコード・コピー/シェア
struct FriendProfileCard: View {
    private static let copiedResetDelay: TimeInterval = 2

    let nickname: String
    let friendCode: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            AvatarCircle(name: nickname, size: 64, color: .accentColor)

            Text(nickname)
                .font(.headline)

            Text(friendCode)
                .font(.system(.title, design: .monospaced).bold())
                .kerning(4)

            Text("このコードで友達に追加してもらえます")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    copy()
                } label: {
                    Label(copied ? "コピー済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                ShareLink(item: "HayaosiApp(仮)でフレンドになろう!マイコード:\(friendCode)") {
                    Label("シェア", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .stroke(Color.accentColor, lineWidth: 2)
        )
    }

    private func copy() {
        UIPasteboard.general.string = friendCode
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.copiedResetDelay * 1_000_000_000))
            copied = false
        }
    }
}

#Preview {
    FriendProfileCard(nickname: "たける", friendCode: "3F8KQ2")
        .padding()
}
