import SwiftUI

/// 起動直後に今日の積み上げだけを小さく伝え、対戦モードの選択を邪魔しない
struct BattleStatusRow: View {
    let streakDayCount: Int
    let todayAnswerCount: Int

    var body: some View {
        HStack(spacing: 8) {
            statusItem(
                text: "連続\(streakDayCount)日",
                systemImage: "flame.fill",
                color: .orange
            )
            statusItem(
                text: "今日\(todayAnswerCount)問",
                systemImage: "checkmark.circle.fill",
                color: .blue
            )
        }
    }

    private func statusItem(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.1)))
    }
}

#Preview {
    BattleStatusRow(streakDayCount: 3, todayAnswerCount: 12)
        .padding()
}
