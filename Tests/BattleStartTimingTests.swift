import XCTest
import Observation
import SwiftData
@testable import HayaosiApp

@MainActor
final class BattleStartTimingTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_000)

    func test_配信された開始時刻まで開始画面を表示する() {
        let scheduledStartAtMS = observedAt.addingTimeInterval(2).timeIntervalSince1970 * 1_000

        let remaining = BattleStartTiming.remainingDisplayTime(
            scheduledStartAtMS: scheduledStartAtMS,
            observedAt: observedAt,
            now: observedAt.addingTimeInterval(0.5)
        )

        XCTAssertEqual(remaining, 1.5, accuracy: 0.001)
    }

    func test_端末時計が進んでいても最低表示時間を確保する() {
        let alreadyPassedStartAtMS = observedAt.addingTimeInterval(-10).timeIntervalSince1970 * 1_000

        let remaining = BattleStartTiming.remainingDisplayTime(
            scheduledStartAtMS: alreadyPassedStartAtMS,
            observedAt: observedAt,
            now: observedAt
        )

        XCTAssertEqual(remaining, BattleRules.minimumMatchStartDisplay, accuracy: 0.001)
    }

    func test_開始時刻と最低表示時間の両方を過ぎると表示を終える() {
        let scheduledStartAtMS = observedAt.addingTimeInterval(2).timeIntervalSince1970 * 1_000

        let remaining = BattleStartTiming.remainingDisplayTime(
            scheduledStartAtMS: scheduledStartAtMS,
            observedAt: observedAt,
            now: observedAt.addingTimeInterval(2.1)
        )

        XCTAssertEqual(remaining, 0)
    }

    func test_進行率は0から1の範囲で増える() {
        let scheduledStartAtMS = observedAt.addingTimeInterval(2).timeIntervalSince1970 * 1_000

        XCTAssertEqual(BattleStartTiming.progress(
            scheduledStartAtMS: scheduledStartAtMS,
            observedAt: observedAt,
            now: observedAt
        ), 0, accuracy: 0.001)
        XCTAssertEqual(BattleStartTiming.progress(
            scheduledStartAtMS: scheduledStartAtMS,
            observedAt: observedAt,
            now: observedAt.addingTimeInterval(1)
        ), 0.5, accuracy: 0.001)
        XCTAssertEqual(BattleStartTiming.progress(
            scheduledStartAtMS: scheduledStartAtMS,
            observedAt: observedAt,
            now: observedAt.addingTimeInterval(3)
        ), 1, accuracy: 0.001)
    }

    func test_開始前の残り時間は制限時間を超えず文字も見えない() {
        let rawStartAtMS = observedAt.timeIntervalSince1970 * 1_000
        let session = StubBattleSession(state: makeRoomState(
            startDelayMS: BattleRules.matchStartDelayMS,
            startedAtMS: rawStartAtMS
        ))
        let beforeStart = observedAt.addingTimeInterval(1)

        XCTAssertEqual(session.remainingTime(at: beforeStart), 20, accuracy: 0.001)
        XCTAssertEqual(session.visibleCharacterCount(at: beforeStart), 0)
    }

    func test_startDelayMSがない旧ルームは待ち時間0として復元する() {
        let dict: [String: Any] = [
            "hostID": "host",
            "status": RoomState.Status.playing.rawValue,
            "settings": RoomState.Settings(
                questionCount: 1,
                timeLimit: 20,
                genre: .englishWord
            ).databaseValue,
            "game": [
                "questionIndex": 0,
                "phase": RoomState.GamePhase.question.rawValue,
                "startedAt": 1_000
            ]
        ]

        let state = RoomState(code: "1234", dict: dict)

        XCTAssertEqual(state?.game?.startDelayMS, 0)
        XCTAssertEqual(state?.game?.effectiveStartedAtMS, 1_000)
    }

    private func makeRoomState(startDelayMS: Double, startedAtMS: Double) -> RoomState {
        let question = RoomState.QuestionPayload(
            id: "q1",
            text: "benefit",
            choices: ["利益", "雰囲気", "優先事項", "恩恵"],
            answer: "恩恵"
        )
        let game = RoomState.Game(
            questionIndex: 0,
            phase: .question,
            startDelayMS: startDelayMS,
            startedAtMS: startedAtMS,
            failedIDs: [],
            answers: [],
            reveal: nil
        )
        return RoomState(
            code: "CPU",
            hostID: "me",
            status: .playing,
            settings: .init(
                questionCount: 1,
                timeLimit: 20,
                genre: .englishWord
            ),
            players: [],
            questions: [question],
            game: game
        )
    }
}

@MainActor
@Observable
private final class StubBattleSession: BattleSession {
    let myID = "me"
    let isHost = true
    let isOnline = false
    let state: RoomState?

    init(state: RoomState) {
        self.state = state
    }

    func startGame(questions: [Question]) async {}
    func rematch() async {}
    func submitAnswer(_ choice: String, visibleCount: Int) {}
    func leave() {}
    func saveResultsIfNeeded(context: ModelContext) {}
}
