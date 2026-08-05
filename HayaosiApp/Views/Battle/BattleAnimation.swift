import SwiftUI

/// 対戦画面の演出で使う時間・動きの定義。画面ごとにバラつかないよう1か所に集める
enum BattleAnimation {
    /// 得点が動いたときの見せ方。跳ねすぎると内容が読み取れないので短く止める
    static let scoreChange: Animation = .snappy(duration: 0.32)
    /// 正解・時間切れの発表が出るとき
    static let reveal: Animation = .spring(response: 0.38, dampingFraction: 0.7)
    /// 早押しボタンの待機中の脈動(1往復)
    static let buzzPulse: Animation = .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    /// 残り時間が少ないときの点滅
    static let urgentPulse: Animation = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)

    /// この秒数を切ったら残り時間を強調する
    static let urgentThreshold: TimeInterval = 5
}
