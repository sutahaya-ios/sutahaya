import SwiftUI

/// 第N問の表示と残り時間。残りが少なくなったら赤く点滅させて緊張感を出す
struct BattleProgressHeader: View {
    let questionNumber: Int
    let totalCount: Int
    /// 残り時間。早押しの受付が終わっている間は nil(時間を出さない)
    let remaining: TimeInterval?
    let timeLimit: TimeInterval

    @State private var isPulsing = false

    private var isUrgent: Bool {
        guard let remaining else { return false }
        return remaining <= BattleAnimation.urgentThreshold
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("第\(questionNumber)問 / \(totalCount)問")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let remaining {
                    Text("残り\(Int(remaining.rounded(.up)))秒")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(isUrgent ? .red : .secondary)
                        .scaleEffect(isUrgent && isPulsing ? 1.15 : 1)
                }
            }

            if let remaining {
                ProgressView(value: min(remaining, timeLimit), total: timeLimit)
                    .tint(isUrgent ? .red : .accentColor)
            }
        }
        .onChange(of: isUrgent) { _, urgent in
            isPulsing = urgent
        }
        .animation(isUrgent ? BattleAnimation.urgentPulse : .default, value: isPulsing)
    }
}

#Preview {
    VStack(spacing: 24) {
        BattleProgressHeader(questionNumber: 3, totalCount: 10, remaining: 14, timeLimit: 20)
        BattleProgressHeader(questionNumber: 3, totalCount: 10, remaining: 3, timeLimit: 20)
        BattleProgressHeader(questionNumber: 3, totalCount: 10, remaining: nil, timeLimit: 20)
    }
    .padding()
}
