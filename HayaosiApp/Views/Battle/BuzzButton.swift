import SwiftUI

/// 早押しボタン。待機中はゆっくり脈動させて「いま押せる」ことを伝え、
/// 押した瞬間は縮ませて反応を返す(通信の返事を待つ前に手応えを出すため)
struct BuzzButton: View {
    private static let diameter: CGFloat = 160
    private static let pulseScale: CGFloat = 1.04

    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            Text("押す!")
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(
                    Circle()
                        .fill(.red)
                        .shadow(color: .red.opacity(0.35), radius: isPulsing ? 18 : 6)
                )
        }
        .buttonStyle(PressScaleStyle())
        .scaleEffect(isPulsing ? Self.pulseScale : 1)
        .animation(BattleAnimation.buzzPulse, value: isPulsing)
        .onAppear { isPulsing = true }
    }
}

/// 押している間だけ縮むボタンスタイル
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    BuzzButton {}
}
