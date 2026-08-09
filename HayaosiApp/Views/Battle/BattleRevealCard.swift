import SwiftUI

/// 制限時間終了後の発表カード。複数の正解者をまとめて表示する
struct BattleRevealCard: View {
    let reveal: RoomState.Reveal
    let correctNames: [String]

    var body: some View {
        VStack(spacing: 12) {
            headline
            Text("正解:\(reveal.correctAnswer)")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if correctNames.count > 1 {
                Text(correctNames.joined(separator: "・"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(reveal.correctIDs.isEmpty ? Color(.secondarySystemBackground) : Color.green.opacity(0.15))
        )
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var headline: some View {
        if reveal.correctIDs.isEmpty {
            Label("時間切れ…", systemImage: "clock.badge.xmark")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if reveal.correctIDs.count == 1, let correctName = correctNames.first {
            Label("\(correctName)が正解!", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else {
            Label("\(reveal.correctIDs.count)人が正解!", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
    }
}

#Preview("正解") {
    BattleRevealCard(
        reveal: .init(correctAnswer: "acquire", correctIDs: ["me"]),
        correctNames: ["ゲスト"]
    )
    .padding()
}

#Preview("時間切れ") {
    BattleRevealCard(
        reveal: .init(correctAnswer: "acquire", correctIDs: []),
        correctNames: []
    )
    .padding()
}
