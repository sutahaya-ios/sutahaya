import SwiftUI

/// 解説を閉じる操作と、読んでから次問へ進む操作を分ける。
struct QuizExplanationSheet: View {
    private static let buttonVerticalPadding: CGFloat = 12

    let question: Question
    let questionNumber: Int
    let userAnswer: QuestionExplanationCard.UserAnswer
    let onNext: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                QuestionExplanationCard(
                    question: question,
                    title: "第\(questionNumber)問",
                    userAnswer: userAnswer
                )
                .padding(20)
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: onNext) {
                    Text("次の問題へ")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, Self.buttonVerticalPadding)
                .background(.bar)
            }
            .navigationTitle("解説")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .tint(.blue)
    }
}
