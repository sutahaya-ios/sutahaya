import Foundation

/// 全画面広告を何試合目に出すかの唯一の出典(要件 §4.2)。
/// 副作用を持たせず、完走した対戦の累計数と次回予定だけで判定する
enum InterstitialSchedule {
    /// 表示間隔(試合)。初回の猶予は設けず、最初から同じ間隔で出す
    static let battleInterval = 3
    /// 出す番を逃したときに、次回予定を早める試合数。
    /// 復習へ抜けた人の表示機会が先送りされ続けるのを防ぐ
    static let missedBattleDiscount = 1

    /// 初めて広告を出す試合番号。猶予が無いので間隔そのもの(3試合目)
    static var firstAdBattleNumber: Int { battleInterval }

    /// 完走数がこの番号に一致した試合のリザルトでだけ広告を出す
    static func shouldPresent(completedBattleCount: Int, nextAdBattleNumber: Int) -> Bool {
        completedBattleCount == nextAdBattleNumber
    }

    /// 表示できたときの次回予定
    static func scheduleAfterPresent(presentedBattleNumber: Int) -> Int {
        presentedBattleNumber + battleInterval
    }

    /// 出す番だったのに表示できなかったときの次回予定。通常より1試合早い
    static func scheduleAfterMiss(missedBattleNumber: Int) -> Int {
        missedBattleNumber + battleInterval - missedBattleDiscount
    }

    /// 予定を過ぎていたら、逃した分だけ予定を早めて現在の完走数へ追いつかせる。
    /// 対戦が完走するたびに呼び、表示機会を逃したことをここで検出する
    static func catchUp(nextAdBattleNumber: Int, completedBattleCount: Int) -> Int {
        var next = nextAdBattleNumber
        while completedBattleCount > next {
            next = scheduleAfterMiss(missedBattleNumber: next)
        }
        return next
    }
}
