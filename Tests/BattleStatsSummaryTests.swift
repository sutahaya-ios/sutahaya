import XCTest
@testable import HayaosiApp

final class BattleStatsSummaryTests: XCTestCase {
    func test_区分を指定するとその区分だけを集計する() {
        let records = [
            makeRecord(matchType: .friend, rank: 1),
            makeRecord(matchType: .friend, rank: 3),
            makeRecord(matchType: .random, rank: 1)
        ]

        let friend = BattleStatsSummary.calculate(records: records, matchType: .friend)

        XCTAssertEqual(friend.battleCount, 2)
        XCTAssertEqual(friend.firstPlaceCount, 1)
        XCTAssertEqual(friend.firstPlaceRate, 0.5)
    }

    func test_区分を指定しないと全区分を合算する() {
        let records = [
            makeRecord(matchType: .friend, rank: 1),
            makeRecord(matchType: .random, rank: 1),
            makeRecord(matchType: .random, rank: 2)
        ]

        let total = BattleStatsSummary.calculate(records: records)

        XCTAssertEqual(total.battleCount, 3)
        XCTAssertEqual(total.firstPlaceCount, 2)
    }

    func test_記録が無い区分は0件になり1位率はダッシュで表示する() {
        let stats = BattleStatsSummary.calculate(
            records: [makeRecord(matchType: .friend, rank: 1)],
            matchType: .random
        )

        XCTAssertEqual(stats.battleCount, 0)
        XCTAssertEqual(stats.firstPlaceCount, 0)
        XCTAssertEqual(stats.firstPlaceRateText, "—")
    }

    private func makeRecord(matchType: BattleMatchType, rank: Int) -> BattleRecord {
        BattleRecord(matchType: matchType, rank: rank, participantCount: 4, score: 60)
    }
}
