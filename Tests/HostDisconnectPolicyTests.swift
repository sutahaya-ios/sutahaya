import XCTest
@testable import HayaosiApp

final class HostDisconnectPolicyTests: XCTestCase {
    func test_ホストの生存中にclosedが届いたら直前状態を復元する() {
        XCTAssertEqual(
            HostDisconnectPolicy.action(
                incomingStatus: .closed,
                isHost: true,
                hasLeft: false,
                lastActiveStatus: .playing
            ),
            .restore(.playing)
        )
    }

    func test_参加者はclosedを即時確定せず再接続を待つ() {
        XCTAssertEqual(
            HostDisconnectPolicy.action(
                incomingStatus: .closed,
                isHost: false,
                hasLeft: false,
                lastActiveStatus: .playing
            ),
            .delayClosure
        )
    }

    func test_明示退出後のclosedはそのまま適用する() {
        XCTAssertEqual(
            HostDisconnectPolicy.action(
                incomingStatus: .closed,
                isHost: true,
                hasLeft: true,
                lastActiveStatus: .playing
            ),
            .apply
        )
    }

    func test_通常の状態更新はそのまま適用する() {
        XCTAssertEqual(
            HostDisconnectPolicy.action(
                incomingStatus: .playing,
                isHost: true,
                hasLeft: false,
                lastActiveStatus: .waiting
            ),
            .apply
        )
    }
}
