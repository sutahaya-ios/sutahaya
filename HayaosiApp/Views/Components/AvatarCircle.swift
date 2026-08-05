import SwiftUI

/// ニックネームの先頭2文字を表示する円形アバター
struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 48
    var color: Color = .blue

    var body: some View {
        Text(String(name.prefix(2)))
            .font(.system(size: size * 0.32, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.15)))
    }

    /// 文字列から決定的に色を選ぶ(起動をまたいでも同じ相手は同じ色になる)
    static func stableColor(for key: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}
