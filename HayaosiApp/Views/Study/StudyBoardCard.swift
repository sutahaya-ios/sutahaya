import SwiftUI

/// マイボードに表示するピン留め済み教材カード
struct StudyBoardCard: View {
    let category: StudyCategory
    let proficiencyRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 追加シートのカードと同じ高さに収めるため、習得率の数字は右上へ置く
            HStack(alignment: .top) {
                Image(systemName: category.studySystemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(category.studyAccentColor)

                Spacer()

                rateLabel
            }

            Text(category.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(category.studyDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            ProgressView(value: progress)
                .tint(category.studyAccentColor)
        }
        .frame(maxWidth: .infinity, minHeight: StudyMaterialCardMetrics.minimumHeight, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(category.studyBackgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var rateLabel: some View {
        HStack(spacing: 4) {
            Text("習得率")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let rateText {
                Text(rateText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
    }

    private var progress: Double {
        min(max(proficiencyRate ?? 0, 0), 1)
    }

    private var rateText: String? {
        proficiencyRate.map { "\(Int(min(max($0, 0), 1) * 100))%" }
    }
}
