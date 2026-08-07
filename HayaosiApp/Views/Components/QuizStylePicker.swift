import SwiftUI

/// 出題形式(即答型/文字送り型)の選択。対戦・ボット対戦・一人練習で共通に使う
struct QuizStylePicker: View {
    @Binding var style: QuizStyle

    var body: some View {
        Picker("出題形式", selection: $style) {
            ForEach(QuizStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.segmented)
    }
}

#Preview {
    Form {
        Section {
            QuizStylePicker(style: .constant(.progressiveChoice))
        } footer: {
            Text(QuizStyle.progressiveChoice.detail)
        }
    }
}
