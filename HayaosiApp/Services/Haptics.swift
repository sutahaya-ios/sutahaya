import UIKit

/// ボタン押下などの触覚フィードバック。設定(振動トグル)でON/OFFできる
@MainActor
enum Haptics {
    static let enabledKey = "hapticsEnabled"

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
