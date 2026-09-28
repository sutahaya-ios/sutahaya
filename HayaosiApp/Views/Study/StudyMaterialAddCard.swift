import SwiftUI

/// 追加シートに表示する実装済み教材カード
struct AvailableStudyMaterialCard: View {
    private static let minimumHeight: CGFloat = 194

    let category: StudyCategory
    let isPinned: Bool
    let onPin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: category.studySystemImage)
                .font(.system(size: 24))
                .foregroundStyle(category.studyAccentColor)

            Text(category.displayName)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)

            Text(category.studyDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(isPinned ? "追加済み" : "＋ 追加") {
                onPin()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isPinned ? Color.secondary : category.studyAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isPinned
                            ? Color(.tertiarySystemFill)
                            : category.studyAccentColor.opacity(0.14)
                    )
            )
            .buttonStyle(.plain)
            .disabled(isPinned)
        }
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(category.studyBackgroundColor)
        )
    }
}

/// 追加シートに表示する近日実装教材カード。操作可能な要素は持たない
struct UpcomingStudyMaterialCard: View {
    private static let minimumHeight: CGFloat = 194

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

            Spacer(minLength: 8)

            Text("乞うご期待")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(.tertiarySystemFill))
                )
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
