import Foundation
import GoogleMobileAds
import Observation

/// 全画面広告の間隔を数える単位。対戦と一人練習は体験が別物なので、別々に数える
enum InterstitialContext {
    case battle
    case quiz

    /// 既存ユーザーの保存値を引き継ぐため、対戦側のキーは変えない
    var completedCountKey: String {
        switch self {
        case .battle: "completedBattleCount"
        case .quiz: "completedQuizCount"
        }
    }

    var nextAdNumberKey: String {
        switch self {
        case .battle: "nextAdBattleNumber"
        case .quiz: "nextAdQuizNumber"
        }
    }
}

/// 広告の初期化・先読み・表示を集約する。
/// 「広告を出すか」の判断はすべてここを通す。
@MainActor
@Observable
final class AdsService {
    static let shared = AdsService()

    private var interstitial: InterstitialAd?
    private var dismissObserver: InterstitialDismissObserver?
    private var isLoadingInterstitial = false
    private var hasStarted = false
    private(set) var isReadyForRequests = false

    private init() {}

    /// アプリ起動後に一度だけ呼ぶ。同意取得 → SDK初期化 → 先読み の順で進める
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await AdConsent.gather()
        await MobileAds.shared.start()
        isReadyForRequests = true
        await preloadInterstitial()
    }

    /// 対戦・一人練習がリザルトへ到達したときに呼ぶ。
    /// リザルトを読んでいる数秒のうちに読み込みを終わらせ、退出時に待たせないための先読み
    func recordSessionFinished(_ context: InterstitialContext) {
        let completedCount = completedCount(for: context) + 1
        setCompletedCount(completedCount, for: context)
        // 前回の出す番を逃していれば、ここで次回予定を早める
        setNextAdNumber(
            InterstitialSchedule.catchUp(
                nextAdBattleNumber: nextAdNumber(for: context),
                completedBattleCount: completedCount
            ),
            for: context
        )
        guard canRequestAds else {
            interstitial = nil
            return
        }
        guard isInterstitialDue(for: context) else { return }
        Task { await preloadInterstitial() }
    }

    /// リザルトから離れる操作(退出・再戦)で呼ぶ。広告を出す番なら表示し、閉じられてから `onFinish` を実行する。
    /// 出す番でない場合と先読みが間に合わなかった場合は、待たせずにそのまま `onFinish` を実行する。
    /// 表示できなかった番は次の対戦完走時に「逃した」と判定され、次回予定が1試合早まる
    func presentInterstitialIfDue(
        for context: InterstitialContext,
        onFinish: @escaping () -> Void
    ) {
        guard canRequestAds,
              isInterstitialDue(for: context),
              let ad = interstitial,
              let viewController = AdPresentationContext.topViewController else {
            if SubscriptionService.shared.hasRemovedAds {
                interstitial = nil
            }
            onFinish()
            return
        }

        setNextAdNumber(
            InterstitialSchedule.scheduleAfterPresent(
                presentedBattleNumber: completedCount(for: context)
            ),
            for: context
        )

        let observer = InterstitialDismissObserver(onDismiss: onFinish)
        // SDKのdelegateはweak参照なので、表示が終わるまでこちらで保持する
        dismissObserver = observer
        ad.fullScreenContentDelegate = observer
        interstitial = nil
        ad.present(from: viewController)
    }

    private func isInterstitialDue(for context: InterstitialContext) -> Bool {
        InterstitialSchedule.shouldPresent(
            completedBattleCount: completedCount(for: context),
            nextAdBattleNumber: nextAdNumber(for: context)
        )
    }

    var canRequestAds: Bool {
        isReadyForRequests && !SubscriptionService.shared.hasRemovedAds
    }

    private func completedCount(for context: InterstitialContext) -> Int {
        UserDefaults.standard.integer(forKey: context.completedCountKey)
    }

    private func setCompletedCount(_ count: Int, for context: InterstitialContext) {
        UserDefaults.standard.set(count, forKey: context.completedCountKey)
    }

    /// 次に広告を出す回数。未保存なら初回予定を使う
    private func nextAdNumber(for context: InterstitialContext) -> Int {
        let stored = UserDefaults.standard.integer(forKey: context.nextAdNumberKey)
        return stored > 0 ? stored : InterstitialSchedule.firstAdBattleNumber
    }

    private func setNextAdNumber(_ number: Int, for context: InterstitialContext) {
        UserDefaults.standard.set(number, forKey: context.nextAdNumberKey)
    }

    private func preloadInterstitial() async {
        guard canRequestAds, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }

        do {
            let loadedInterstitial = try await InterstitialAd.load(
                with: AdUnit.interstitial,
                request: Request()
            )
            guard canRequestAds else { return }
            interstitial = loadedInterstitial
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
