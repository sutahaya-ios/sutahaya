import Foundation

/// 対戦ルールの定数(要件 §5.1)。数値はここが唯一の出典。
/// オンライン対戦・ボット対戦の両方が参照するため、Firebaseに依存しない `Battle/` に置く
enum BattleRules {
    static let maxPlayers = 8
    static let minPlayersToStart = 2
    static let correctPoint = 1
    static let wrongPoint = -1
    /// 回答権を得てから回答するまでの制限時間
    static let answerTimeLimit: TimeInterval = 10
    /// 正解・時間切れの発表を見せる時間
    static let revealDuration: TimeInterval = 3
    static let codeDigits = 4
    /// ルームコードが重複したときの再抽選回数
    static let createAttempts = 5
}
