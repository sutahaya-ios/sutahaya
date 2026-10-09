import XCTest
@testable import HayaosiApp

final class InterstitialScheduleTests: XCTestCase {
    func test_間隔に満たないうちは広告を出さない() {
        let first = InterstitialSchedule.firstAdBattleNumber
        for battleCount in 0..<first {
            XCTAssertFalse(
                InterstitialSchedule.shouldPresent(
                    completedBattleCount: battleCount,
                    nextAdBattleNumber: first
                ),
                "\(battleCount)試合目で広告が出ている"
            )
        }
    }

    /// 初回の猶予は設けず、3試合目から出す
    func test_3試合目で初めて広告を出す() {
        XCTAssertEqual(InterstitialSchedule.firstAdBattleNumber, 3)
        XCTAssertTrue(
            InterstitialSchedule.shouldPresent(completedBattleCount: 3, nextAdBattleNumber: 3)
        )
    }

    func test_表示できたら3試合ごとに広告を出す() {
        XCTAssertEqual(shownBattleNumbers(upTo: 12, missedBattleNumbers: []), [3, 6, 9, 12])
    }

    /// 出す番を逃した人は、次の機会が通常より1試合早く来る
    func test_逃した次の予定は1試合早まる() {
        XCTAssertEqual(InterstitialSchedule.scheduleAfterMiss(missedBattleNumber: 6), 8)
        XCTAssertEqual(InterstitialSchedule.scheduleAfterPresent(presentedBattleNumber: 6), 9)
    }

    func test_6試合目を逃すと次は8試合目になる() {
        XCTAssertEqual(shownBattleNumbers(upTo: 11, missedBattleNumbers: [6]), [3, 8, 11])
    }

    /// 逃し続けると機会は2試合ごとに来る。これ以上は詰まらない
    func test_逃し続けると機会は2試合ごとに来る() {
        let everyBattle = Set(1...13)
        XCTAssertEqual(
            dueBattleNumbers(upTo: 13, missedBattleNumbers: everyBattle),
            [3, 5, 7, 9, 11, 13]
        )
    }

    /// 詰まったあとでも、表示できた時点で通常の3試合間隔へ戻る
    func test_表示できたら3試合間隔へ戻る() {
        XCTAssertEqual(shownBattleNumbers(upTo: 13, missedBattleNumbers: [3, 5, 7]), [9, 12])
    }

    func test_予定を過ぎていたら追いつくまで予定を早める() {
        XCTAssertEqual(
            InterstitialSchedule.catchUp(nextAdBattleNumber: 3, completedBattleCount: 3),
            3
        )
        XCTAssertEqual(
            InterstitialSchedule.catchUp(nextAdBattleNumber: 3, completedBattleCount: 4),
            5
        )
        XCTAssertEqual(
            InterstitialSchedule.catchUp(nextAdBattleNumber: 3, completedBattleCount: 8),
            9
        )
    }

    /// 実際に広告が出る試合番号
    private func shownBattleNumbers(upTo lastBattle: Int, missedBattleNumbers: Set<Int>) -> [Int] {
        simulate(upTo: lastBattle, missedBattleNumbers: missedBattleNumbers).shown
    }

    /// 出す番が回ってくる試合番号(逃した分を含む)
    private func dueBattleNumbers(upTo lastBattle: Int, missedBattleNumbers: Set<Int>) -> [Int] {
        simulate(upTo: lastBattle, missedBattleNumbers: missedBattleNumbers).due
    }

    /// `AdsService` と同じ順序で予定を更新する
    private func simulate(
        upTo lastBattle: Int,
        missedBattleNumbers: Set<Int>
    ) -> (due: [Int], shown: [Int]) {
        var next = InterstitialSchedule.firstAdBattleNumber
        var due: [Int] = []
        var shown: [Int] = []

        for battleCount in 1...lastBattle {
            next = InterstitialSchedule.catchUp(
                nextAdBattleNumber: next,
                completedBattleCount: battleCount
            )
            guard InterstitialSchedule.shouldPresent(
                completedBattleCount: battleCount,
                nextAdBattleNumber: next
            ) else { continue }

            due.append(battleCount)
            guard !missedBattleNumbers.contains(battleCount) else { continue }
            shown.append(battleCount)
            next = InterstitialSchedule.scheduleAfterPresent(presentedBattleNumber: battleCount)
        }
        return (due, shown)
    }
}
