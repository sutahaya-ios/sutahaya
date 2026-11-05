import SwiftUI

/// 練習・リザルトで共用する、下端固定の補助操作と主操作。
struct QuizActionBar: View {
    private static let verticalPadding: CGFloat = 12

    let secondaryTitle: String
    let secondarySystemImage: String
    let primaryTitle: String
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSecondary) {
                Label(secondaryTitle, systemImage: secondarySystemImage)
            }
            .buttonStyle(.bordered)

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, Self.verticalPadding)
        .background(.bar)
    }
}
