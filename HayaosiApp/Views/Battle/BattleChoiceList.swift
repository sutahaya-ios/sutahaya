import SwiftUI

/// 文字送り型の4択。**押した瞬間が「早押し+回答」**なので、問題が始まった時点から全員に見えている。
/// 一度押したら変更できず、誤答したらその問題には再回答できない(要件 §5.1.2)
struct BattleChoiceList: View {
    let choices: [String]
    /// 自分が押した選択肢(未回答ならnil)
    let myChoice: String?
    /// いま回答できるか(未回答・誤答なし・出題中)
    let canAnswer: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    onSelect(choice)
                } label: {
                    Text(choice)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: choice))
                .disabled(!canAnswer)
                .opacity(dimmed(choice) ? 0.45 : 1)
            }
        }
    }

    private func tint(for choice: String) -> Color {
        myChoice == choice ? .orange : .accentColor
    }

    /// 回答済みなら、選ばなかった選択肢を薄くして「もう変えられない」ことを示す
    private func dimmed(_ choice: String) -> Bool {
        myChoice != nil && myChoice != choice
    }
}

#Preview("回答前") {
    BattleChoiceList(
        choices: ["〜を捨てる、断念する", "〜を吸収する", "〜を成し遂げる", "〜を維持する"],
        myChoice: nil,
        canAnswer: true,
        onSelect: { _ in }
    )
    .padding()
}

#Preview("回答後") {
    BattleChoiceList(
        choices: ["〜を捨てる、断念する", "〜を吸収する", "〜を成し遂げる", "〜を維持する"],
        myChoice: "〜を吸収する",
        canAnswer: false,
        onSelect: { _ in }
    )
    .padding()
}
