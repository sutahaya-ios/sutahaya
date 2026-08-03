import XCTest
@testable import HayaosiApp

/// 文字送り型の表示量の計算。全端末で同じ進み具合になることが前提なので、
/// 経過時間から一意に決まることをここで担保する
final class ProgressiveRevealTests: XCTestCase {
    private let timeLimit: TimeInterval = 20
    /// revealRatio 0.6 → 20秒設定なら12秒で全文が出そろう
    private var revealDuration: TimeInterval { timeLimit * ProgressiveReveal.revealRatio }

    func test_開始直後は1文字だけ見える() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 20, elapsed: 0, timeLimit: timeLimit)

        XCTAssertEqual(count, ProgressiveReveal.initialCharacters)
    }

    func test_半分の時間で半分ほど見える() {
        let count = ProgressiveReveal.visibleCount(
            totalCharacters: 21,
            elapsed: revealDuration / 2,
            timeLimit: timeLimit
        )

        XCTAssertEqual(count, 11, "1文字目 + 残り20文字の半分")
    }

    func test_表示時間を過ぎたら全文が見える() {
        let count = ProgressiveReveal.visibleCount(
            totalCharacters: 20,
            elapsed: revealDuration,
            timeLimit: timeLimit
        )

        XCTAssertEqual(count, 20)
    }

    func test_制限時間いっぱいまで進んでも文字数を超えない() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 20, elapsed: 999, timeLimit: timeLimit)

        XCTAssertEqual(count, 20)
    }

    func test_経過時間が進むほど見える文字数は減らない() {
        var previous = 0
        for elapsed in stride(from: 0.0, through: timeLimit, by: 0.1) {
            let count = ProgressiveReveal.visibleCount(
                totalCharacters: 30,
                elapsed: elapsed,
                timeLimit: timeLimit
            )
            XCTAssertGreaterThanOrEqual(count, previous, "経過\(elapsed)秒で表示量が戻った")
            previous = count
        }
        XCTAssertEqual(previous, 30)
    }

    func test_端末の時計がずれて経過時間がマイナスでも1文字は見える() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 20, elapsed: -5, timeLimit: timeLimit)

        XCTAssertEqual(count, ProgressiveReveal.initialCharacters)
    }

    func test_問題文が空なら0文字() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 0, elapsed: 1, timeLimit: timeLimit)

        XCTAssertEqual(count, 0)
    }

    func test_制限時間が0なら全文を出す() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 20, elapsed: 1, timeLimit: 0)

        XCTAssertEqual(count, 20, "0除算で表示が壊れるより全文表示に倒す")
    }
}
