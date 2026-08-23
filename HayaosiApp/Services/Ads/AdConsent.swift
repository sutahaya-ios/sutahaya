import AppTrackingTransparency
import UserMessagingPlatform

/// 広告表示前に必要な同意を取得する(要件 §4.2)
@MainActor
enum AdConsent {
    static func gather() async {
        await updateConsentInfo()
        await requestTrackingAuthorization()
    }

    /// 同意状態をSDKへ取り込むだけで、フォームは表示しない。
    /// EEA向け同意フォームの文面はAdMobコンソール側に持つため、本番アプリIDを登録するまで出せない
    /// (サンプルIDのフォームは「続ける」を押しても閉じず、画面を塞ぐ)。表示はSTATUS.mdのタスクとして残す
    private static func updateConsentInfo() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
        } catch {
            // 取得できなくても非パーソナライズ広告は出せるので、ログだけ残して続行する
            print("[Ads] 同意情報の取得に失敗: \(error.localizedDescription)")
        }
    }

    /// 拒否されてもアプリは通常どおり動く(広告がパーソナライズされなくなるだけ)
    private static func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}
