import Foundation

/// 対戦ルールの定数(要件 §5.1)。数値はここが唯一の出典。
/// オンライン対戦・CPU対戦の両方が参照するため、Firebaseに依存しない `Battle/` に置く
enum BattleRules {
    /// ロビーから1問目へ切り替わる前に開始合図を見せる時間
    static let matchStartDelay: TimeInterval = 2
    /// 端末時計が進んでいても開始合図が一瞬で消えないための最低表示時間
    static let minimumMatchStartDisplay: TimeInterval = 0.5
    static let matchStartDelayMS = matchStartDelay * 1_000
    static let maxPlayers = 8
    static let minPlayersToStart = 2
    /// 正解者内の順位ごとの得点。4位以降は `laterCorrectPoint`
    static let rankedCorrectPoints = [20, 10, 5]
    static let laterCorrectPoint = 1
    static let wrongPoint = -10
    /// 正解・時間切れの発表を見せる時間
    static let revealDuration: TimeInterval = 3
    static let codeDigits = 4
    /// ルームコードが重複したときの再抽選回数
    static let createAttempts = 5

    static func correctPoint(for rank: Int) -> Int {
        guard rank > 0 else { return 0 }
        let index = rank - 1
        return rankedCorrectPoints.indices.contains(index) ? rankedCorrectPoints[index] : laterCorrectPoint
    }
}
