import XCTest
@testable import HayaosiApp

final class BattleScoringTests: XCTestCase {
    func test_正解者内の順位で20点10点5点1点を配点する() {
        let answers = [
            answer(uid: "wrong", choice: "誤答", time: 50),
            answer(uid: "first", choice: "正答", time: 100),
            answer(uid: "second", choice: "正答", time: 200),
            answer(uid: "third", choice: "正答", time: 300),
            answer(uid: "fourth", choice: "正答", time: 400)
        ]

        let result = BattleScoring.result(
            answers: answers,
            correctAnswer: "正答",
            participantIDs: ["first", "second", "third", "fourth", "wrong", "silent"]
        )

        XCTAssertEqual(result.correctIDs, ["first", "second", "third", "fourth"])
        XCTAssertEqual(result.pointChanges["first"], 20)
        XCTAssertEqual(result.pointChanges["second"], 10)
        XCTAssertEqual(result.pointChanges["third"], 5)
        XCTAssertEqual(result.pointChanges["fourth"], 1)
        XCTAssertEqual(result.pointChanges["wrong"], -10)
        XCTAssertNil(result.pointChanges["silent"], "無回答は0点なので更新しない")
    }

    func test_同時刻は参加者の基本順で順位を決める() {
        let answers = [
            answer(uid: "guest", choice: "正答", time: 100),
            answer(uid: "host", choice: "正答", time: 100)
        ]

        let result = BattleScoring.result(
            answers: answers,
            correctAnswer: "正答",
            participantIDs: ["host", "guest"]
        )

        XCTAssertEqual(result.correctIDs, ["host", "guest"])
        XCTAssertEqual(result.pointChanges["host"], 20)
        XCTAssertEqual(result.pointChanges["guest"], 10)
    }

    func test_無回答だけなら得点変更も正解者も無い() {
        let result = BattleScoring.result(
            answers: [],
            correctAnswer: "正答",
            participantIDs: ["host", "guest"]
        )

        XCTAssertTrue(result.correctIDs.isEmpty)
        XCTAssertTrue(result.wrongIDs.isEmpty)
        XCTAssertTrue(result.pointChanges.isEmpty)
    }

    func test_制限時間の初期値は5秒で選択肢の先頭にある() {
        XCTAssertEqual(QuizDefaults.timeLimit, 5)
        XCTAssertEqual(QuizDefaults.timeLimitOptions, [5, 10, 20, 30])
        XCTAssertTrue(QuizDefaults.timeLimitOptions.contains(QuizDefaults.timeLimit),
                      "既定値が選択肢に無いとPickerで選択状態が表示されない")
    }

    func test_RoomStateが複数の正解者を順位順に復元する() {
        let room = RoomState(code: "1234", dict: [
            "hostID": "host",
            "status": RoomState.Status.playing.rawValue,
            "settings": RoomState.Settings(
                questionCount: 1,
                timeLimit: 25,
                genre: .englishWord
            ).databaseValue,
            "game": [
                "questionIndex": 0,
                "phase": RoomState.GamePhase.reveal.rawValue,
                "startedAt": 1_000,
                "reveal": [
                    "correctAnswer": "正答",
                    "correctIDs": ["first", "second"]
                ]
            ]
        ])

        XCTAssertEqual(room?.game?.reveal?.correctIDs, ["first", "second"])
    }

    func test_RoomStateが前問から遅れて届いた回答とお手つきを無視する() {
        let room = RoomState(code: "1234", dict: [
            "hostID": "host",
            "status": RoomState.Status.playing.rawValue,
            "game": [
                "questionIndex": 1,
                "phase": RoomState.GamePhase.question.rawValue,
                "startedAt": 1_000,
                "answers": [
                    "host": ["questionIndex": 0, "choice": "前問", "ts": 900, "visibleCount": 1],
                    "guest": ["questionIndex": 1, "choice": "今問", "ts": 1_100, "visibleCount": 2]
                ],
                "failed": [
                    "host": ["questionIndex": 0],
                    "guest": ["questionIndex": 1]
                ]
            ]
        ])

        XCTAssertEqual(room?.game?.answers.map(\.uid), ["guest"])
        XCTAssertEqual(room?.game?.failedIDs, ["guest"])
    }

    private func answer(uid: String, choice: String, time: Double) -> RoomState.Answer {
        RoomState.Answer(uid: uid, questionIndex: 0, choice: choice, answeredAtMS: time, visibleCount: 1)
    }
}
