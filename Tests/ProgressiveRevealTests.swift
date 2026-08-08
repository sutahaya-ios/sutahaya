import XCTest
@testable import HayaosiApp

/// 単語を1文字ずつ見せる計算。全端末で同じ進み具合になることが前提なので、
/// 経過時間から一意に決まることをここで担保する
final class ProgressiveRevealTests: XCTestCase {
    private var interval: TimeInterval { ProgressiveReveal.characterInterval }

    func test_開始直後は1文字だけ見える() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 7, elapsed: 0)

        XCTAssertEqual(count, ProgressiveReveal.initialCharacters)
    }

    func test_1文字ぶんの時間が経つごとに1文字増える() {
        let total = 7
        for step in 0..<total {
            // 区間の中央で測る(境界のブレを避ける)
            let elapsed = interval * (Double(step) + 0.5)
            let count = ProgressiveReveal.visibleCount(totalCharacters: total, elapsed: elapsed)

            XCTAssertEqual(count, min(total, 1 + step), "経過\(elapsed)秒")
        }
    }

    func test_全文が出そろったらそれ以上増えない() {
        let total = 7
        let count = ProgressiveReveal.visibleCount(totalCharacters: total, elapsed: 999)

        XCTAssertEqual(count, total)
    }

    func test_表示量は時間が進んでも戻らない() {
        var previous = 0
        for elapsed in stride(from: 0.0, through: 10.0, by: 0.05) {
            let count = ProgressiveReveal.visibleCount(totalCharacters: 12, elapsed: elapsed)
            XCTAssertGreaterThanOrEqual(count, previous, "経過\(elapsed)秒で表示量が戻った")
            previous = count
        }
        XCTAssertEqual(previous, 12)
    }

    func test_端末の時計がずれて経過時間がマイナスでも1文字は見える() {
        let count = ProgressiveReveal.visibleCount(totalCharacters: 7, elapsed: -5)

        XCTAssertEqual(count, ProgressiveReveal.initialCharacters)
    }

    func test_1文字の単語は最初から全部見えている() {
        XCTAssertEqual(ProgressiveReveal.visibleCount(totalCharacters: 1, elapsed: 0), 1)
        XCTAssertEqual(ProgressiveReveal.visibleCount(totalCharacters: 0, elapsed: 1), 0)
    }

    // MARK: - CPUの回答タイミング算出(文字数 → 秒)

    func test_指定文字数が出るまでの時間を求める() {
        XCTAssertEqual(ProgressiveReveal.time(forVisibleCount: 1), 0, accuracy: 0.001)
        XCTAssertEqual(ProgressiveReveal.time(forVisibleCount: 4), interval * 3, accuracy: 0.001)
    }

    func test_文字数の計算と時間の計算が一致する() {
        let total = 9
        for target in 1...total {
            let at = ProgressiveReveal.time(forVisibleCount: target)
            // ちょうどの時刻は境界なので、わずかに進めた時点で目標文字数に達している
            let visible = ProgressiveReveal.visibleCount(totalCharacters: total, elapsed: at + 0.01)

            XCTAssertEqual(visible, target, "\(target)文字目")
        }
    }

    func test_全文表示までの時間は文字数に比例する() {
        let short = ProgressiveReveal.fullRevealDuration(totalCharacters: 4)
        let long = ProgressiveReveal.fullRevealDuration(totalCharacters: 7)

        XCTAssertEqual(long - short, interval * 3, accuracy: 0.001)
    }
}
