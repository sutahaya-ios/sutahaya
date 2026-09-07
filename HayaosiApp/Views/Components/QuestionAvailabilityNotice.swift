import SwiftUI

/// 選択した範囲に問題がないことと、選び直す方法を伝える共通表示
struct QuestionAvailabilityNotice: View {
    let category: StudyCategory
    let difficulties: [StudyDifficulty]

    init(category: StudyCategory, difficulty: StudyDifficulty) {
        self.category = category
        difficulties = [difficulty]
    }

    init(category: StudyCategory, difficulties: [StudyDifficulty]) {
        self.category = category
        self.difficulties = difficulties
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectionDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("この範囲の問題は順次追加しています")
                    .font(.subheadline.weight(.semibold))

                Text("他の難易度を選んでください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
    }

    private var selectionDescription: String {
        let difficultyDescription = difficulties
            .map(\.starDisplay)
            .joined(separator: " / ")
        return "\(category.displayName) \(difficultyDescription)"
    }
}

#Preview {
    QuestionAvailabilityNotice(
        category: .toeic,
        difficulties: [.two, .three, .four, .five]
    )
    .padding()
}
