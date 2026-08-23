import Foundation

/// 広告ユニットIDの出典。Debugビルドでは必ずGoogleのテストIDを使う
/// (自分の本番広告を叩くとAdMobアカウントが停止されるため)
enum AdUnit {
    private static let testBanner = "ca-app-pub-3940256099942544/2934735716"
    private static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"

    private static let productionBanner = "ca-app-pub-7792161969727895/5370561920"
    private static let productionInterstitial = "ca-app-pub-7792161969727895/7743619994"

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
