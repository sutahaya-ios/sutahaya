import SwiftUI

/// 英単語カテゴリと、カテゴリ内の5段階難易度を選ぶ共通UI
struct WordClassificationPicker: View {
    @Binding var category: WordCategory
    @Binding var difficulty: WordDifficulty

    var body: some View {
        Picker("ジャンル", selection: $category) {
            ForEach(WordCategory.allCases) { category in
                Text(category.displayName).tag(category)
            }
        }
        Picker("レベル", selection: $difficulty) {
            ForEach(WordDifficulty.allCases) { difficulty in
                Text(difficulty.starDisplay).tag(difficulty)
            }
        }
    }
}

#Preview {
    @Previewable @State var category = WordCategory.juniorHigh
    @Previewable @State var difficulty = WordDifficulty.one
    NavigationStack {
        Form {
            WordClassificationPicker(category: $category, difficulty: $difficulty)
        }
    }
}
