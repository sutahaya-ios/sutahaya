import XCTest
@testable import HayaosiApp

final class ProfileInputPolicyTests: XCTestCase {
    func test_ニックネームの前後空白を除去する() {
        XCTAssertEqual(ProfileInputPolicy.normalizedNickname("  Alice  "), "Alice")
    }

    func test_空のニックネームは既定値へ戻す() {
        XCTAssertEqual(ProfileInputPolicy.normalizedNickname(" \n "), "ゲスト")
    }

    func test_ニックネームを上限で切り詰める() {
        let value = String(repeating: "あ", count: ProfileInputPolicy.nicknameMaxLength + 1)
        XCTAssertEqual(
            ProfileInputPolicy.normalizedNickname(value).count,
            ProfileInputPolicy.nicknameMaxLength
        )
    }
}
