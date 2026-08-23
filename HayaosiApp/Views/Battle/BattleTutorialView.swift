import SwiftUI

/// 初回ユーザーが、実際の対戦と同じ「文字送り＋選択肢タップ」を1問だけ体験する画面
struct BattleTutorialView: View {
    private static let question = "apple"
    private static let answer = "りんご"
    private static let choices = ["りんご", "本", "水", "学校"]

    @Environment(\.dismiss) private var dismiss
    @State private var startedAtMS = Date().timeIntervalSince1970 * 1_000
    @State private var selectedChoice: String?

    private var isCorrect: Bool {
        selectedChoice == Self.answer
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Label("1問だけやってみよう", systemImage: "bolt.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.orange)

                    Text("文字が少しずつ表示されます")
                        .font(.headline)

                    BattleQuestionText(
                        text: Self.question,
                        mode: .progressing(startedAtMS: startedAtMS)
                    )

                    Text("答えが分かった瞬間に選択肢をタップ！\n選択肢のタップが、早押しと回答を兼ねています")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    BattleChoiceList(
                        choices: Self.choices,
                        myChoice: selectedChoice,
                        canAnswer: !isCorrect
                    ) { choice in
                        selectedChoice = choice
                    }

                    feedback
                }
                .padding()
            }
            .navigationTitle("遊び方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var feedback: some View {
        if isCorrect {
            VStack(spacing: 12) {
                Label("正解！そのタイミングが早押しです", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button("対戦へ") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if selectedChoice != nil {
            VStack(spacing: 12) {
                Label("違います。もう一度選んでみよう", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Button("文字送りを最初から見る") {
                    selectedChoice = nil
                    startedAtMS = Date().timeIntervalSince1970 * 1_000
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    BattleTutorialView()
}
