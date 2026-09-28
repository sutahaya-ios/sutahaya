import SwiftUI

/// 学習カテゴリと、カテゴリ内の5段階難易度を選ぶ共通UI
struct StudyClassificationPicker: View {
    @Binding var category: StudyCategory
    @Binding var difficulty: StudyDifficulty

    var body: some View {
        Picker("ジャンル", selection: $category) {
            ForEach(StudyCategory.allCases) { category in
                Text(category.displayName).tag(category)
            }
        }
        Picker("レベル", selection: $difficulty) {
            ForEach(StudyDifficulty.allCases) { difficulty in
                Text(difficulty.starDisplay).tag(difficulty)
            }
        }
    }
}

#Preview {
    @Previewable @State var category = StudyCategory.juniorHigh
    @Previewable @State var difficulty = StudyDifficulty.one
    NavigationStack {
        Form {
            StudyClassificationPicker(category: $category, difficulty: $difficulty)
        }
    }
}
