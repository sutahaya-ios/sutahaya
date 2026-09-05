import XCTest
@testable import HayaosiApp

final class OnlineRoomConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "OnlineRoomConfigurationTests")
        defaults.removePersistentDomain(forName: "OnlineRoomConfigurationTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "OnlineRoomConfigurationTests")
        defaults = nil
        super.tearDown()
    }

    func testInitialValuesUseExistingQuizDefaults() {
        let configuration = OnlineRoomConfiguration(defaults: defaults)

        XCTAssertEqual(configuration, .default)
    }

    func testSavedConfigurationCanBeRestored() {
        let expected = OnlineRoomConfiguration(
            category: .highSchool,
            difficulty: .three,
            questionCount: 15,
            timeLimit: 20
        )

        expected.save(to: defaults)

        XCTAssertEqual(OnlineRoomConfiguration(defaults: defaults), expected)
    }

    func testInvalidStoredOptionsFallBackToDefaults() {
        defaults.set("unknown", forKey: OnlineRoomConfiguration.categoryKey)
        defaults.set(99, forKey: OnlineRoomConfiguration.difficultyKey)
        defaults.set(3, forKey: OnlineRoomConfiguration.questionCountKey)
        defaults.set(7, forKey: OnlineRoomConfiguration.timeLimitKey)

        XCTAssertEqual(OnlineRoomConfiguration(defaults: defaults), .default)
    }

    func testRoomSettingsCapQuestionCountAtAvailableQuestions() {
        let configuration = OnlineRoomConfiguration(
            category: .toeic,
            difficulty: .five,
            questionCount: 20,
            timeLimit: 30
        )

        let settings = configuration.roomSettings(availableQuestionCount: 7)

        XCTAssertEqual(settings.questionCount, 7)
        XCTAssertEqual(settings.timeLimit, 30)
        XCTAssertEqual(settings.wordCategory, .toeic)
        XCTAssertEqual(settings.wordDifficulty, .five)
    }

    func testExistingRoomSettingsBecomeEditorInitialValues() {
        let configuration = OnlineRoomConfiguration(settings: .init(
            questionCount: 7,
            timeLimit: 5,
            genre: .englishWord,
            wordCategory: .highSchool,
            wordDifficulty: .four
        ))

        XCTAssertEqual(configuration.category, .highSchool)
        XCTAssertEqual(configuration.difficulty, .four)
        XCTAssertEqual(configuration.questionCount, 7)
        XCTAssertEqual(configuration.timeLimit, 5)
    }
}

final class RoomInviteLifecycleTests: XCTestCase {
    func testPendingInviteIsVisibleOnlyBeforeThirtySecondBoundary() {
        let sentAt = Date(timeIntervalSince1970: 1_000)
        let invite = makeInvite(status: .pending, sentAt: sentAt)

        XCTAssertTrue(invite.isVisibleInvitation(at: sentAt.addingTimeInterval(29.999)))
        XCTAssertFalse(invite.isVisibleInvitation(at: sentAt.addingTimeInterval(30)))
    }

    func testAcceptedAndCancelledInvitesAreNeverShownAsNewInvites() {
        let sentAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(makeInvite(status: .accepted, sentAt: sentAt)
            .isVisibleInvitation(at: sentAt.addingTimeInterval(1)))
        XCTAssertFalse(makeInvite(status: .cancelled, sentAt: sentAt)
            .isVisibleInvitation(at: sentAt.addingTimeInterval(1)))
    }

    func testNotificationIdentityChangesOnlyWhenGenerationChanges() {
        let first = makeInvite(status: .pending, generation: 1)
        let replacement = makeInvite(status: .pending, generation: 2)

        XCTAssertEqual(first.id, replacement.id)
        XCTAssertNotEqual(first.notificationID, replacement.notificationID)
    }

    func testRoomStateDecodesStableRoomInstanceID() {
        let room = RoomState(code: "1234", dict: [
            "roomInstanceID": "room-instance",
            "hostID": "host",
            "status": RoomState.Status.waiting.rawValue,
            "playerSlots": ["0": "host", "2": "guest"],
            "players": [
                "host": ["nickname": "Host", "score": 0, "joinedAt": 1]
            ]
        ])

        XCTAssertEqual(room?.roomInstanceID, "room-instance")
        XCTAssertEqual(room?.playerSlot(for: "guest"), 2)
        XCTAssertEqual(room?.firstAvailablePlayerSlot, 1)
    }

    func testRoomStateDecodesFirebaseArrayPlayerSlots() {
        let room = RoomState(code: "1234", dict: [
            "roomInstanceID": "room-instance",
            "hostID": "host",
            "status": RoomState.Status.waiting.rawValue,
            "playerSlots": ["host"],
            "players": [
                "host": ["nickname": "Host", "score": 0, "joinedAt": 1]
            ]
        ])

        XCTAssertEqual(room?.playerSlot(for: "host"), 0)
        XCTAssertEqual(room?.firstAvailablePlayerSlot, 1)
    }

    private func makeInvite(
        status: RoomInvite.Status,
        generation: Int = 1,
        sentAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> RoomInvite {
        RoomInvite(
            id: "room-instance_sender",
            roomCode: "1234",
            fromNickname: "Sender",
            roomInstanceID: "room-instance",
            fromUID: "sender",
            toUID: "recipient",
            status: status,
            generation: generation,
            sentAt: sentAt
        )
    }
}

final class RTDBJoinRetryPolicyTests: XCTestCase {
    func testRecognizesOnlyTheCachelessFirebaseCoreOfflineError() {
        let offline = NSError(
            domain: "com.firebase.core",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unable to get latest value for query /rooms/1234, client offline with no active listeners and no matching disk cache entries"
            ]
        )

        XCTAssertTrue(RTDBJoinRetryPolicy.isTransientOffline(offline))
    }

    func testDoesNotRetryPermissionDeniedOrOtherCoreErrors() {
        let permissionDenied = NSError(
            domain: "com.firebase",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )
        let otherCoreError = NSError(
            domain: "com.firebase.core",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Firebase configuration error"]
        )

        XCTAssertFalse(RTDBJoinRetryPolicy.isTransientOffline(permissionDenied))
        XCTAssertFalse(RTDBJoinRetryPolicy.isTransientOffline(otherCoreError))
        XCTAssertTrue(RTDBJoinRetryPolicy.isPermissionDenied(permissionDenied))
        XCTAssertFalse(RTDBJoinRetryPolicy.isPermissionDenied(otherCoreError))
    }

    func testJoinBudgetLeavesRoomBeforeTheAcceptClaimLeaseEnds() {
        XCTAssertLessThan(
            RTDBJoinRetryPolicy.acceptOperationBudget,
            .seconds(RoomInvite.acceptingLease)
        )
        XCTAssertEqual(RTDBJoinRetryPolicy.maxOfflineReadRetries, 1)
        XCTAssertEqual(RTDBJoinRetryPolicy.maxTransientJoinRetries, 12)
        XCTAssertLessThanOrEqual(
            RTDBJoinRetryPolicy.transientJoinRetryDelay * RTDBJoinRetryPolicy.maxTransientJoinRetries,
            RTDBJoinRetryPolicy.connectionWait
        )
    }
}
