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

    func test_回答受付境界は開始時刻以上かつ締切時刻以下だけをacceptedにする() {
        let game = RoomState.Game(
            questionIndex: 2,
            phase: .question,
            startDelayMS: 500,
            startedAtMS: 1_000,
            failedIDs: [],
            answers: [
                answer(uid: "before", choice: "正答", time: 1_499, questionIndex: 2),
                answer(uid: "at-start", choice: "誤答", time: 1_500, questionIndex: 2),
                answer(uid: "at-deadline", choice: "正答", time: 6_500, questionIndex: 2),
                answer(uid: "after", choice: "正答", time: 6_501, questionIndex: 2),
                answer(uid: "previous", choice: "正答", time: 2_000, questionIndex: 1),
                answer(uid: "outsider", choice: "正答", time: 2_500, questionIndex: 2)
            ],
            reveal: nil
        )

        let accepted = BattleAnswerAcceptance.acceptedAnswers(
            in: game,
            timeLimit: 5,
            participantIDs: ["before", "at-start", "at-deadline", "after", "previous"]
        )
        let scoring = BattleScoring.result(
            answers: accepted,
            correctAnswer: "正答",
            participantIDs: ["before", "at-start", "at-deadline", "after", "previous"]
        )

        XCTAssertEqual(accepted.map(\.uid), ["at-start", "at-deadline"])
        XCTAssertEqual(scoring.wrongIDs, ["at-start"])
        XCTAssertEqual(scoring.correctIDs, ["at-deadline"])
        XCTAssertEqual(scoring.pointChanges["at-start"], BattleRules.wrongPoint)
        XCTAssertEqual(scoring.pointChanges["at-deadline"], BattleRules.correctPoint(for: 1))
        XCTAssertNil(scoring.pointChanges["after"], "締切後回答は順位にも得点にも含めない")
    }

    func test_Firebase保存成功でもサーバー確定時刻が締切後ならacceptedではない() {
        let lateAnswer = answer(uid: "guest", choice: "正答", time: 6_001)

        XCTAssertFalse(BattleAnswerAcceptance.isAccepted(
            lateAnswer,
            questionIndex: 0,
            effectiveStartedAtMS: 1_000,
            timeLimit: 5,
            participantIDs: ["host", "guest"]
        ))
    }

    func test_回答write直後の出題中readに回答が未反映でも拒否と扱わない() {
        let game = RoomState.Game(
            questionIndex: 0,
            phase: .question,
            startDelayMS: 0,
            startedAtMS: 1_000,
            failedIDs: [],
            answers: [],
            reveal: nil
        )

        XCTAssertEqual(BattleAnswerAcceptance.submissionConfirmation(
            in: game,
            uid: "guest",
            timeLimit: 5,
            participantIDs: ["host", "guest"]
        ), .pending)
    }

    func test_host確定中のreadに回答が未反映でも拒否と扱わない() {
        let game = RoomState.Game(
            questionIndex: 0,
            phase: .reveal,
            startDelayMS: 0,
            startedAtMS: 1_000,
            failedIDs: [],
            answers: [],
            reveal: nil
        )

        XCTAssertEqual(BattleAnswerAcceptance.submissionConfirmation(
            in: game,
            uid: "guest",
            timeLimit: 5,
            participantIDs: ["host", "guest"]
        ), .pending)
    }

    func test_RoomStateはserver確定前のtimestampを0秒の回答として復元しない() {
        let room = RoomState(code: "1234", dict: [
            "hostID": "host",
            "status": RoomState.Status.playing.rawValue,
            "game": [
                "questionIndex": 0,
                "phase": RoomState.GamePhase.question.rawValue,
                "startedAt": 1_000,
                "answers": [
                    "guest": [
                        "questionIndex": 0,
                        "choice": "正答",
                        "ts": [".sv": "timestamp"],
                        "visibleCount": 1
                    ]
                ]
            ]
        ])

        XCTAssertEqual(room?.game?.answers, [])
    }

    func test_回答write直後の確定回答は期限内だけacceptedにする() {
        let accepted = RoomState.Game(
            questionIndex: 0,
            phase: .question,
            startDelayMS: 0,
            startedAtMS: 1_000,
            failedIDs: [],
            answers: [answer(uid: "guest", choice: "正答", time: 5_999)],
            reveal: nil
        )
        let rejected = RoomState.Game(
            questionIndex: 0,
            phase: .question,
            startDelayMS: 0,
            startedAtMS: 1_000,
            failedIDs: [],
            answers: [answer(uid: "guest", choice: "正答", time: 6_001)],
            reveal: nil
        )

        XCTAssertEqual(BattleAnswerAcceptance.submissionConfirmation(
            in: accepted,
            uid: "guest",
            timeLimit: 5,
            participantIDs: ["host", "guest"]
        ), .accepted)
        XCTAssertEqual(BattleAnswerAcceptance.submissionConfirmation(
            in: rejected,
            uid: "guest",
            timeLimit: 5,
            participantIDs: ["host", "guest"]
        ), .rejected)
    }

    func test_受付終了後は時刻内でもホスト確定結果に無い後着回答を順位から除外する() {
        let game = RoomState.Game(
            questionIndex: 0,
            phase: .reveal,
            startDelayMS: 0,
            startedAtMS: 1_000,
            failedIDs: ["wrong"],
            answers: [
                answer(uid: "correct", choice: "正答", time: 2_000),
                answer(uid: "wrong", choice: "誤答", time: 2_100),
                answer(uid: "arrived-after-close", choice: "正答", time: 2_200)
            ],
            reveal: .init(correctAnswer: "正答", correctIDs: ["correct"])
        )

        let confirmed = BattleAnswerAcceptance.confirmedAnswers(
            in: game,
            timeLimit: 5,
            participantIDs: ["correct", "wrong", "arrived-after-close"]
        )

        XCTAssertEqual(confirmed.map(\.uid), ["correct", "wrong"])
    }

    func test_出題中はaccepted回答に対応する得点が未反映なら順位を表示できない() {
        let answers = [answer(uid: "guest", choice: "正答", time: 2_000)]

        XCTAssertFalse(BattleAnswerAcceptance.scoresMatch(
            answers: answers,
            correctAnswer: "正答",
            participantIDs: ["host", "guest"],
            baseScores: ["host": 0, "guest": 0],
            currentScores: ["host": 0, "guest": 0]
        ))
    }

    func test_出題中はaccepted回答と得点が一致した時だけ順位を表示できる() {
        let correctAnswers = [answer(uid: "guest", choice: "正答", time: 2_000)]
        let wrongAnswers = [answer(uid: "host", choice: "誤答", time: 2_000)]

        XCTAssertTrue(BattleAnswerAcceptance.scoresMatch(
            answers: correctAnswers,
            correctAnswer: "正答",
            participantIDs: ["host", "guest"],
            baseScores: ["host": 5, "guest": 10],
            currentScores: ["host": 5, "guest": 30]
        ))
        XCTAssertTrue(BattleAnswerAcceptance.scoresMatch(
            answers: wrongAnswers,
            correctAnswer: "正答",
            participantIDs: ["host", "guest"],
            baseScores: ["host": 5, "guest": 10],
            currentScores: ["host": -5, "guest": 10]
        ))
    }

    func test_制限時間の選択肢にカテゴリごとの既定値が含まれる() {
        XCTAssertEqual(QuizDefaults.timeLimit, 5)
        XCTAssertEqual(QuizDefaults.timeLimitOptions(for: .juniorHigh), [5, 10, 20, 30])
        XCTAssertEqual(QuizDefaults.timeLimitOptions(for: .spiNonVerbal), [30, 60, 120, 180])

        for category in StudyCategory.allCases {
            XCTAssertTrue(
                QuizDefaults.timeLimitOptions(for: category).contains(category.defaultTimeLimit),
                "\(category.displayName)の既定値が選択肢に無いとPickerで選択状態が表示されない"
            )
        }
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

    private func answer(
        uid: String,
        choice: String,
        time: Double,
        questionIndex: Int = 0
    ) -> RoomState.Answer {
        RoomState.Answer(
            uid: uid,
            questionIndex: questionIndex,
            choice: choice,
            answeredAtMS: time,
            visibleCount: 1
        )
    }
}
