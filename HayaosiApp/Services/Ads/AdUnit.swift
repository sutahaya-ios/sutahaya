import Foundation

/// 広告ユニットIDの出典。Debugビルドでは必ずGoogleのテストIDを使う
/// (自分の本番広告を叩くとAdMobアカウントが停止されるため)
enum AdUnit {
    private static let testBanner = "ca-app-pub-3940256099942544/2934735716"
    private static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"

    // TODO: AdMobでアプリを登録して本番の広告ユニットIDに差し替える(STATUS.md タスク4)
    private static let productionBanner = testBanner
    private static let productionInterstitial = testInterstitial

    static var banner: String {
        #if DEBUG
        testBanner
        #else
        productionBanner
        #endif
    }

    static var interstitial: String {
        #if DEBUG
        testInterstitial
        #else
        productionInterstitial
        #endif
    }
}
