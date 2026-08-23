import XCTest
@testable import HayaosiApp

final class InterstitialScheduleTests: XCTestCase {
    func test_初回の猶予中は広告を出さない() {
        for battleCount in 0...InterstitialSchedule.freeBattleCount {
            XCTAssertFalse(
                InterstitialSchedule.shouldPresent(completedBattleCount: battleCount),
                "\(battleCount)試合目で広告が出ている"
            )
        }
    }

    func test_猶予の次の試合で初めて広告を出す() {
        XCTAssertTrue(InterstitialSchedule.shouldPresent(completedBattleCount: 4))
    }

    func test_初回表示のあとは間隔ごとに広告を出す() {
        XCTAssertEqual(shownBattleNumbers(upTo: 13), [4, 7, 10, 13])
    }

    private func shownBattleNumbers(upTo lastBattle: Int) -> [Int] {
        (1...lastBattle).filter { InterstitialSchedule.shouldPresent(completedBattleCount: $0) }
    }
}
