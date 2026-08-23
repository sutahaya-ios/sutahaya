import Foundation

/// 全画面広告を何試合目に出すかの唯一の出典(要件 §4.2)。
/// 副作用を持たせず、完走した対戦の累計数だけで判定する
enum InterstitialSchedule {
    /// 広告を出さない最初の試合数。初回体験を守るための猶予
    static let freeBattleCount = 3
    /// 猶予を過ぎたあとの表示間隔(試合)
    static let battleInterval = 3

    /// 初めて広告を出す試合番号
    private static var firstAdBattleNumber: Int { freeBattleCount + 1 }

    /// 完走した対戦の累計が `completedBattleCount` のとき、リザルト退出時に広告を出すか
    /// 例:猶予3・間隔3なら 4, 7, 10, ... 試合目で true
    static func shouldPresent(completedBattleCount: Int) -> Bool {
        guard completedBattleCount >= firstAdBattleNumber else { return false }
        return (completedBattleCount - firstAdBattleNumber) % battleInterval == 0
    }
}
