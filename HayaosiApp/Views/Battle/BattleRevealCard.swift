import SwiftUI

/// 正解・時間切れの発表カード。誰が取ったのかを一目で分かるようにする
struct BattleRevealCard: View {
    let reveal: RoomState.Reveal
    /// 得点したプレイヤー名(時間切れ・不明な場合はnil)
    let scorerName: String?

    var body: some View {
        VStack(spacing: 12) {
            headline
            Text("正解:\(reveal.correctAnswer)")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(reveal.byTimeout ? Color(.secondarySystemBackground) : Color.green.opacity(0.15))
        )
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var headline: some View {
        if reveal.byTimeout {
            Label("時間切れ…", systemImage: "clock.badge.xmark")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if let scorerName {
            Label("\(scorerName)が正解!", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
    }
}

#Preview("正解") {
    BattleRevealCard(
        reveal: .init(correctAnswer: "acquire", scorerID: "me", byTimeout: false),
        scorerName: "ゲスト"
    )
    .padding()
}

#Preview("時間切れ") {
    BattleRevealCard(
        reveal: .init(correctAnswer: "acquire", scorerID: nil, byTimeout: true),
        scorerName: nil
    )
    .padding()
}
