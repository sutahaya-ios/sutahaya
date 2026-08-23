import Foundation
import GoogleMobileAds

/// 広告の初期化・先読み・表示を集約する。
/// 「広告を出すか」の判断はすべてここを通す(広告非表示サブスクを入れるときも、分岐を足すのはこのクラスだけで済む)
@MainActor
final class AdsService {
    static let shared = AdsService()

    private static let completedBattleCountKey = "completedBattleCount"

    private var interstitial: InterstitialAd?
    private var dismissObserver: InterstitialDismissObserver?
    private var isLoadingInterstitial = false
    private var hasStarted = false

    private init() {}

    /// アプリ起動後に一度だけ呼ぶ。同意取得 → SDK初期化 → 先読み の順で進める
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await AdConsent.gather()
        await MobileAds.shared.start()
        await preloadInterstitial()
    }

    /// 対戦がリザルトへ到達したときに呼ぶ。
    /// リザルトを読んでいる数秒のうちに読み込みを終わらせ、退出時に待たせないための先読み
    func recordBattleFinished() {
        completedBattleCount += 1
        guard isInterstitialDue else { return }
        Task { await preloadInterstitial() }
    }

    /// リザルトからの退出時に呼ぶ。広告を出す番なら表示し、閉じられてから `onFinish` を実行する。
    /// 出す番でない場合と先読みが間に合わなかった場合は、待たせずにそのまま `onFinish` を実行する
    func presentInterstitialIfDue(onFinish: @escaping () -> Void) {
        guard isInterstitialDue,
              let ad = interstitial,
              let viewController = AdPresentationContext.topViewController else {
            onFinish()
            return
        }

        let observer = InterstitialDismissObserver(onDismiss: onFinish)
        // SDKのdelegateはweak参照なので、表示が終わるまでこちらで保持する
        dismissObserver = observer
        ad.fullScreenContentDelegate = observer
        interstitial = nil
        ad.present(from: viewController)
    }

    private var isInterstitialDue: Bool {
        InterstitialSchedule.shouldPresent(completedBattleCount: completedBattleCount)
    }

    private var completedBattleCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.completedBattleCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.completedBattleCountKey) }
    }

    private func preloadInterstitial() async {
        guard interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }

        do {
            interstitial = try await InterstitialAd.load(with: AdUnit.interstitial, request: Request())
        } catch {
            // 在庫切れ・オフラインでも起きる。広告を諦めるだけで、遷移は止めない
            print("[Ads] 全画面広告の読み込みに失敗: \(error.localizedDescription)")
        }
    }
}

/// 全画面広告が閉じられたことを受け取り、止めていた画面遷移を再開させる
private final class InterstitialDismissObserver: NSObject, FullScreenContentDelegate {
    private var onDismiss: (() -> Void)?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[Ads] 全画面広告の表示に失敗: \(error.localizedDescription)")
        finish()
    }

    /// 表示失敗と閉じるが両方届いても、遷移を二度走らせない
    private func finish() {
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}
