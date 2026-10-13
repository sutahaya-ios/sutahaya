import SwiftUI

/// 追加シートに表示する実装済み教材カード。カード全体を押すたびに追加・解除が切り替わる
struct AvailableStudyMaterialCard: View {
    private static let minimumHeight: CGFloat = 104
    private static let cornerRadius: CGFloat = 16
    private static let pinnedBorderWidth: CGFloat = 2

    let category: StudyCategory
    let isPinned: Bool
    let onTogglePin: () -> Void

    var body: some View {
        Button(action: onTogglePin) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: category.studySystemImage)
                        .font(.system(size: 24))
                        .foregroundStyle(category.studyAccentColor)

                    Spacer()

                    pinMark
                }

                Text(category.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                Text(category.studyDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(category.studyBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(category.studyAccentColor, lineWidth: isPinned ? Self.pinnedBorderWidth : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.displayName)
        .accessibilityValue(isPinned ? "追加済み" : "未追加")
        .accessibilityHint(isPinned ? "押すと学習タブから外します" : "押すと学習タブへ追加します")
        .accessibilityAddTraits(.isButton)
    }

    private var pinMark: some View {
        Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isPinned ? category.studyAccentColor : Color.secondary.opacity(0.5))
    }
}

/// 追加シートに表示する近日実装教材カード。操作可能な要素は持たない
struct UpcomingStudyMaterialCard: View {
    private static let minimumHeight: CGFloat = 104

    let material: UpcomingMaterial

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: material.systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(material.accentColor)

                Spacer()

                Text("近日")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .foregroundStyle(material.accentColor)
                    .background(
                        Capsule()
                            .fill(material.accentColor.opacity(0.16))
                    )
            }

            Text(material.displayName)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)

            Text(material.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

        }
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(material.accentColor.opacity(0.12))
        )
        .opacity(0.55)
        .accessibilityElement(children: .combine)
    }
}
