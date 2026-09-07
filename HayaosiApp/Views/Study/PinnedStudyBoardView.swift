import SwiftUI

/// ピン留め済み教材を追加順に並べるマイボード
struct PinnedStudyBoardView: View {
    private static let gridSpacing: CGFloat = 12
    private static let columns = [
        GridItem(.flexible(), spacing: gridSpacing),
        GridItem(.flexible(), spacing: gridSpacing)
    ]

    let categories: [StudyCategory]
    let records: [AnswerRecord]
    let questions: [Question]
    let isEditing: Bool
    let onUnpin: (StudyCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("マイボード")
                .font(.headline)

            if categories.isEmpty {
                emptyCard
            } else {
                LazyVGrid(columns: Self.columns, spacing: Self.gridSpacing) {
                    ForEach(categories) { category in
                        boardCell(for: category)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func boardCell(for category: StudyCategory) -> some View {
        let summary = CategoryProficiencySummary.calculate(
            records: records,
            questions: questions,
            category: category
        )

        ZStack(alignment: .topLeading) {
            if isEditing {
                StudyBoardCard(
                    category: category,
                    proficiencyRate: summary.proficiencyRate
                )
            } else {
                NavigationLink {
                    CategoryHeatmapView(category: category)
                } label: {
                    StudyBoardCard(
                        category: category,
                        proficiencyRate: summary.proficiencyRate
                    )
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                Button {
                    withAnimation {
                        onUnpin(category)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .background(Circle().fill(Color(.systemBackground)))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("\(category.displayName)をピン留めから外す")
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "pin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("下の「教材を追加」から選んでください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        )
    }
}
