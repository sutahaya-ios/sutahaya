import SwiftUI

/// マイボードに表示するピン留め済み教材カード
struct StudyBoardCard: View {
    private static let minimumHeight: CGFloat = 188

    let category: StudyCategory
    let proficiencyRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: category.studySystemImage)
                .font(.system(size: 24))
                .foregroundStyle(category.studyAccentColor)

            Text(category.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(category.studyDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 8)

            ProgressView(value: progress)
                .tint(category.studyAccentColor)

            HStack {
                Text("習得率")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let rateText {
                    Text(rateText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(category.studyBackgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var progress: Double {
        min(max(proficiencyRate ?? 0, 0), 1)
    }

    private var rateText: String? {
        proficiencyRate.map { "\(Int(min(max($0, 0), 1) * 100))%" }
    }
}
