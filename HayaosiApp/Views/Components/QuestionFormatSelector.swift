import SwiftUI

/// 学習とフレンド対戦で共用する、全形式を含む横スクロールの選択肢
struct QuestionFormatSelector: View {
    private static let chipHeight: CGFloat = 44
    private static let cornerRadius: CGFloat = 12

    let formats: [QuestionFormat]
    @Binding var selection: QuestionFormat?

    private var options: [QuestionFormat?] {
        [nil] + formats.map(Optional.some)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { format in
                    formatChip(format)
                }
            }
        }
    }

    private func formatChip(_ format: QuestionFormat?) -> some View {
        let isSelected = selection == format
        return Button {
            selection = format
        } label: {
            Text(format?.displayName ?? "すべて")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .frame(minHeight: Self.chipHeight)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius)
                )
        }
        .buttonStyle(SoundButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
