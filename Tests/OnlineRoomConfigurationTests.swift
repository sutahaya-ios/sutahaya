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
}
