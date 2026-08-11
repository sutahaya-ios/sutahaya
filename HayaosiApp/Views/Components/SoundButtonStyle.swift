import SwiftUI

/// 見た目を変えず、押し下げた瞬間に決定音を鳴らす共通スタイル
struct SoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                guard isPressed, !wasPressed else { return }
                SoundPlayer.shared.play(.button)
            }
    }
}
