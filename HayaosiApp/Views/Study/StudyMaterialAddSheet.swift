import SwiftUI

/// 実装済み・近日実装の教材を一覧する追加シート
struct StudyMaterialAddSheet: View {
    private static let gridSpacing: CGFloat = 12
    private static let columns = [
        GridItem(.flexible(), spacing: gridSpacing),
        GridItem(.flexible(), spacing: gridSpacing)
    ]

    @Environment(\.dismiss) private var dismiss
    @Binding var pinnedCategories: [StudyCategory]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Self.gridSpacing) {
                    ForEach(StudyCategory.allCases) { category in
                        AvailableStudyMaterialCard(
                            category: category,
                            isPinned: pinnedCategories.contains(category),
                            onPin: { pin(category) }
                        )
                    }

                    ForEach(UpcomingMaterial.allCases) { material in
                        UpcomingStudyMaterialCard(material: material)
                    }
                }
                .padding()
            }
            .navigationTitle("教材を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func pin(_ category: StudyCategory) {
        guard !pinnedCategories.contains(category) else {
            return
        }
        pinnedCategories.append(category)
    }
}
