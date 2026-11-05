import XCTest
@testable import HayaosiApp

final class HostDisconnectPolicyTests: XCTestCase {
    func test_ルーム作成のpermissionDeniedは次のコードを試す() {
        let error = NSError(domain: "com.firebase", code: 1)
        XCTAssertTrue(RoomCreationPolicy.shouldTryNextCode(after: error))
    }

    func test_ルーム作成のそれ以外のエラーは再抽選しない() {
        let errors = [
            NSError(domain: "com.firebase", code: 2),
            NSError(domain: "com.firebase.core", code: 1),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        ]
        for error in errors {
            XCTAssertFalse(RoomCreationPolicy.shouldTryNextCode(after: error))
        }
    }

    func test_参加中のルーム消失は解散表示にする() {
        XCTAssertTrue(RoomSnapshotLossPolicy.shouldShowClosed(hasState: true, hasLeft: false))
    }

    func test_状態取得前のルーム消失は解散表示にしない() {
        XCTAssertFalse(RoomSnapshotLossPolicy.shouldShowClosed(hasState: false, hasLeft: false))
        XCTAssertFalse(RoomSnapshotLossPolicy.shouldShowClosed(hasState: false, hasLeft: true))
    }

    func test_明示退出後のルーム消失は解散表示にしない() {
        XCTAssertFalse(RoomSnapshotLossPolicy.shouldShowClosed(hasState: true, hasLeft: true))
    }

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
