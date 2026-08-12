import SwiftUI

/// プロフィールアイコンに選べる絵文字プリセット。画像アップロードは扱わない(要件 §10 とFirebase Storage未導入のため)
enum ProfileIcon {
    static let presets = [
        "📚", "✏️", "🎯", "🔥", "⭐️", "🚀", "🐱", "🐶", "🦊", "🐼",
        "🦁", "🐸", "🍀", "🌟", "⚡️", "🎓", "🧠", "🏆", "🎮", "🍩"
    ]
    static let none = ""
}

/// プリセット絵文字からアイコンを選ぶグリッド。`selection` が空文字ならイニシャルアバターに戻す
struct ProfileIconPicker: View {
    @Binding var selection: String

    private static let tileSize: CGFloat = 44
    private let columns = [GridItem(.adaptive(minimum: tileSize), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            iconTile(icon: ProfileIcon.none) {
                Image(systemName: "textformat")
                    .foregroundStyle(.secondary)
            }

            ForEach(ProfileIcon.presets, id: \.self) { icon in
                iconTile(icon: icon) {
                    Text(icon).font(.title2)
                }
            }
        }
    }

    private func iconTile(icon: String, @ViewBuilder label: () -> some View) -> some View {
        let isSelected = icon == selection
        return Button {
            selection = icon
        } label: {
            label()
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                .overlay(Circle().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
