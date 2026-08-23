import GoogleMobileAds
import SwiftUI

/// 画面下端に置くバナー広告。読み込めなければ空白のまま高さだけを保つ
struct AdBannerView: View {
    /// 画面幅に合わせた高さを持つバナー。アプリは縦固定なので一度決めれば変わらない
    private let adSize = currentOrientationAnchoredAdaptiveBanner(width: AdPresentationContext.bannerWidth)

    var body: some View {
        BannerRepresentable(adSize: adSize)
            .frame(width: adSize.size.width, height: adSize.size.height)
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdUnit.banner
        banner.rootViewController = AdPresentationContext.topViewController
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // 在庫切れ・オフラインで日常的に起きる。表示されないだけで実害はないのでログのみ
            print("[Ads] バナー広告の読み込みに失敗: \(error.localizedDescription)")
        }
    }
}
