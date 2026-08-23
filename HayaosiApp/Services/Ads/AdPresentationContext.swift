import UIKit

/// 広告SDKが要求する「表示元のViewController」と、バナーの基準幅を取り出す。
/// SwiftUIからはVCを直接持てないため、最前面のVCを窓口として使う
@MainActor
enum AdPresentationContext {
    /// 画面幅が取れなかったときに使う最小のバナー幅
    private static let fallbackBannerWidth: CGFloat = 320

    /// 最前面のViewController。取得できなければ nil(呼び出し側は広告を諦める)
    static var topViewController: UIViewController? {
        guard let root = activeScene?.keyWindow?.rootViewController else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// バナーの基準幅。アプリは縦固定なので実行中に変わらない
    static var bannerWidth: CGFloat {
        activeScene?.screen.bounds.width ?? fallbackBannerWidth
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
