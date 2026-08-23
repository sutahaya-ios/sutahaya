import XCTest
import SwiftData
@testable import HayaosiApp

/// CPU対戦の進行・採点のテスト。
/// 実時間のタイマーと乱数を注入で固定し、分割リファクタ前後で挙動が変わらないことを担保する
@MainActor
final class CPUBattleSessionTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Question.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    // MARK: - テスト用の注入物

    /// 実時間を待たず、予約された動作をテスト側の合図で発火させるタイマー
    @MainActor
    final class ManualTimer {
        private(set) var pending: [(seconds: TimeInterval, action: @MainActor () -> Void)] = []

        var scheduler: CPUBattleSession.TimerScheduler {
            { [weak self] seconds, action in
                self?.pending.append((seconds, action))
                return Task {}
            }
        }

        /// 予約順にすべて発火する(発火中に増えた予約も処理する)。
        /// 進行の正しさはセッション側のガード(round・phase)が守るので、順序には依存しない
        func fireAll(limit: Int = 200) {
            var count = 0
            while !pending.isEmpty, count < limit {
                let next = pending.removeFirst()
                next.action()
                count += 1
            }
        }

        /// 先頭の予約だけを発火する。「CPUだけが答えた」途中状態を作るのに使う
        func fireFirst() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().action()
        }

        /// **今この時点で**予約済みのものだけを発火する(発火中に増えた予約は残す)。
        /// 「発表の経過だけ進めて、次の問題のタイマーは触らない」という検証に使う
        func fireExisting() {
            let batch = pending
            pending.removeAll()
            batch.forEach { $0.action() }
        }
    }

    /// CPUが一切参加しない判断(人間の操作だけを検証するため)
    private var silentCPU: CPUAnswerStrategy {
        CPUAnswerStrategy(random: { $0.upperBound })  // participates: 1.0 < p は常に偽
    }

    /// CPUが必ず参加し、最短で・必ず正解する判断
    private var aggressiveCPU: CPUAnswerStrategy {
        CPUAnswerStrategy(random: { $0.lowerBound })  // participates: 0 < p は常に真、choice は正答
    }

    private func makeQuestions(count: Int) -> [Question] {
        let context = ModelContext(container)
        return (1...count).map { index in
            let question = Question(
                id: "q\(index)",
                genre: .englishWord,
                type: .multipleChoice,
                text: "word\(index)",
                choices: ["a\(index)", "w1", "w2", "w3"],
                answer: "a\(index)"
            )
            context.insert(question)
            return question
        }
    }

    private func makeSession(cpuCount: Int = 1,
                             strategy: CPUAnswerStrategy? = nil,
                             timer: ManualTimer) -> CPUBattleSession {
        CPUBattleSession(
            nickname: "テスト",
            settings: .init(questionCount: 10, timeLimit: 20, genre: .englishWord),
            cpuCount: cpuCount,
            strategy: strategy ?? silentCPU,
            timerScheduler: timer.scheduler
        )
    }

    /// いま出ている問題の正答(選択肢はシャッフルされるため状態から取る)
    private func currentAnswer(_ session: CPUBattleSession) -> String {
        session.state?.questions[session.state?.game?.questionIndex ?? 0].answer ?? ""
    }

    // MARK: - 初期状態

    func test_開始前はロビー待機でゲームが無い() {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 2, timer: timer)

        XCTAssertEqual(session.state?.status, .waiting)
        XCTAssertNil(session.state?.game)
        XCTAssertEqual(session.state?.players.count, 3, "自分+CPU2体")
        XCTAssertEqual(session.state?.players.map(\.score), [0, 0, 0])
    }

    // MARK: - 対戦開始

    func test_開始すると第1問の出題中になる() async {
        let timer = ManualTimer()
        let session = makeSession(timer: timer)

        await session.startGame(questions: makeQuestions(count: 3))

        XCTAssertEqual(session.state?.status, .playing)
        XCTAssertEqual(session.state?.game?.phase, .question)
        XCTAssertEqual(session.state?.game?.questionIndex, 0)
        XCTAssertEqual(session.state?.game?.startDelayMS, BattleRules.matchStartDelayMS)
        XCTAssertEqual(session.state?.questions.count, 3)
        XCTAssertEqual(timer.pending.first?.seconds, BattleRules.matchStartDelay + 20)
    }

    // MARK: - 採点

    func test_正解した時点で加点され他の回答を待つ間も反映される() async {
        let timer = ManualTimer()
        // 参加するCPUを1体置き、まだ答えていない=待ちが発生する状況を作る
        let session = makeSession(cpuCount: 1, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 3)

        let me = session.state?.players.first { $0.id == "me" }
        XCTAssertEqual(me?.score, BattleRules.correctPoint(for: 1), "1番目の正解として即座に加点される")
        XCTAssertEqual(session.state?.game?.phase, .question, "CPUがまだ答えていないので発表しない")
        XCTAssertNil(session.state?.game?.reveal)
        XCTAssertEqual(session.state?.game?.answers.first?.visibleCount, 3, "何文字目で答えたかが記録される")
    }

    func test_誤答すると即時に回答権を失い減点される() async {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 1, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer("わざと間違い", visibleCount: 2)
        session.submitAnswer(currentAnswer(session), visibleCount: 5) // ロックされているので無視されるはず

        let me = session.state?.players.first { $0.id == "me" }
        XCTAssertEqual(me?.score, BattleRules.wrongPoint, "誤答は順位に関係なく即座に減点される")
        XCTAssertEqual(session.state?.game?.failedIDs.contains("me"), true)
        XCTAssertEqual(session.state?.game?.answers.count, 1, "2回目の回答は受け付けない")
        XCTAssertEqual(session.state?.game?.phase, .question)
    }

    func test_今回間違えた問題IDだけをリザルト用に返す() async {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 1, strategy: silentCPU, timer: timer)
        let questions = makeQuestions(count: 2)
        await session.startGame(questions: questions)

        session.submitAnswer("わざと間違い", visibleCount: 2)

        XCTAssertEqual(session.wrongQuestionIDs, [questions[0].id])
    }

    func test_あとから先に正解した人が出ると得点が置き直される() async {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 1, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 3)
        XCTAssertEqual(session.state?.players.first { $0.id == "me" }?.score, BattleRules.correctPoint(for: 1))

        timer.fireFirst() // CPUが後から正解する

        XCTAssertEqual(session.state?.players.first { $0.id == "me" }?.score,
                       BattleRules.correctPoint(for: 1),
                       "先に答えた自分の順位は変わらない")
        XCTAssertEqual(session.state?.players.first { $0.id == "cpu-normal" }?.score,
                       BattleRules.correctPoint(for: 2),
                       "後から答えたCPUは2番目の得点。二重加算にならない")
    }

    func test_参加を見送ったCPUは待たずに発表へ進む() async {
        let timer = ManualTimer()
        // silentCPU はこの問題に参加しないので、待っても永遠に回答しない
        let session = makeSession(cpuCount: 1, strategy: silentCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 3)

        XCTAssertEqual(session.state?.game?.phase, .reveal, "答える人が残っていないので制限時間を待たない")
        XCTAssertEqual(session.state?.game?.reveal?.correctIDs, ["me"])
        XCTAssertEqual(session.state?.players.first { $0.id == "cpu-normal" }?.score, 0, "無回答は0点")
    }

    func test_複数の正解者を正解者内の回答順で採点する() async {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 3, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 1))

        timer.fireExisting()

        let players = session.state?.players ?? []
        XCTAssertEqual(session.state?.game?.phase, .reveal)
        XCTAssertEqual(session.state?.game?.reveal?.correctIDs.count, 3)
        XCTAssertEqual(players.first { $0.id == "cpu-normal" }?.score, 20)
        XCTAssertEqual(players.first { $0.id == "cpu-strong" }?.score, 10)
        XCTAssertEqual(players.first { $0.id == "cpu-weak" }?.score, 5)
        XCTAssertEqual(players.first { $0.id == "me" }?.score, 0, "無回答は0点")
    }

    func test_全員が回答し終えたら制限時間を待たずに発表へ進む() async {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 1, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        timer.fireFirst() // CPUだけが回答した状態

        XCTAssertEqual(session.state?.game?.phase, .question, "自分がまだ答えていないので発表しない")

        session.submitAnswer(currentAnswer(session), visibleCount: 4)

        XCTAssertEqual(session.state?.game?.phase, .reveal, "全員が答え終わったので制限時間前に発表する")
        XCTAssertEqual(session.state?.game?.reveal?.correctIDs.count, 2)
        XCTAssertEqual(session.state?.game?.reveal?.correctIDs.first, "cpu-normal", "先に答えたCPUが1位")
        let me = session.state?.players.first { $0.id == "me" }
        XCTAssertEqual(me?.score, BattleRules.correctPoint(for: 2), "2番目の正解として加点される")
    }

    // MARK: - 進行

    func test_最終問題のあとリザルトへ進む() async {
        let timer = ManualTimer()
        let session = makeSession(timer: timer)
        await session.startGame(questions: makeQuestions(count: 1))

        session.submitAnswer(currentAnswer(session), visibleCount: 1)
        timer.fireAll() // 発表時間の経過を発火

        XCTAssertEqual(session.state?.status, .finished)
        XCTAssertEqual(session.state?.game?.phase, .finished)
    }

    func test_発表時間が終わると次の問題へ進む() async {
        let timer = ManualTimer()
        // 既定の silentCPU はこの問題に参加しないので、自分が答えた時点で発表へ進む
        let session = makeSession(timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 1)
        XCTAssertEqual(session.state?.game?.phase, .reveal)

        timer.fireExisting() // 発表時間の経過

        XCTAssertEqual(session.state?.status, .playing)
        XCTAssertEqual(session.state?.game?.questionIndex, 1)
        XCTAssertEqual(session.state?.game?.phase, .question)
        XCTAssertEqual(session.state?.game?.startDelayMS, 0, "開始演出は1問目の前だけ")
    }

    func test_前問で予約されたCPU回答が遅れても次問へ混ざらない() async throws {
        let timer = ManualTimer()
        let session = makeSession(cpuCount: 1, strategy: aggressiveCPU, timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        let staleCPUAnswer = try XCTUnwrap(timer.pending.first).action
        let firstQuestionTimeout = try XCTUnwrap(timer.pending.last).action
        firstQuestionTimeout()

        XCTAssertEqual(session.state?.game?.phase, .reveal)
        let advanceToSecondQuestion = try XCTUnwrap(timer.pending.last).action
        advanceToSecondQuestion()

        XCTAssertEqual(session.state?.game?.questionIndex, 1)
        XCTAssertEqual(session.state?.game?.phase, .question)
        staleCPUAnswer()

        XCTAssertTrue(session.state?.game?.answers.isEmpty == true,
                      "前問の予約回答は世代が違うため次問へ記録しない")
        XCTAssertTrue(session.state?.game?.failedIDs.isEmpty == true)
        XCTAssertTrue(session.state?.players.allSatisfy { $0.score == 0 } == true,
                      "前問の遅延回答で次問の得点を変更しない")
    }

    // MARK: - 順位(同点同順位)

    func test_同点は同順位になる() {
        let players = [
            RoomState.Player(id: "a", nickname: "A", score: 3, joinedAtMS: 0),
            RoomState.Player(id: "b", nickname: "B", score: 3, joinedAtMS: 1),
            RoomState.Player(id: "c", nickname: "C", score: 1, joinedAtMS: 2)
        ]

        let ranked = BattleRanking.ranked(players)

        XCTAssertEqual(BattleRanking.rank(of: ranked[0], in: ranked), 1)
        XCTAssertEqual(BattleRanking.rank(of: ranked[1], in: ranked), 1, "同点は同順位")
        XCTAssertEqual(BattleRanking.rank(of: ranked[2], in: ranked), 3, "次の順位は人数ぶん飛ぶ")
    }

    func test_スコアボードは回答順に並び正誤を表示する() {
        let players = [
            RoomState.Player(id: "host", nickname: "ホスト", score: 1, joinedAtMS: 30),
            RoomState.Player(id: "first", nickname: "先着", score: -1, joinedAtMS: 10),
            RoomState.Player(id: "second", nickname: "次", score: 1, joinedAtMS: 20)
        ]
        let answers = [
            RoomState.Answer(uid: "first", questionIndex: 0, choice: "誤答", answeredAtMS: 100, visibleCount: 2),
            RoomState.Answer(uid: "second", questionIndex: 0, choice: "正答", answeredAtMS: 200, visibleCount: 3)
        ]

        let entries = BattleScoreBoard.entries(
            players: players,
            hostID: "host",
            answers: answers,
            failedIDs: ["first"],
            correctIDs: ["second"]
        )

        XCTAssertEqual(entries.map(\.id), ["first", "second", "host"])
        XCTAssertEqual(entries.map(\.answerRank), [1, 2, nil])
        XCTAssertEqual(entries[0].result, .wrong)
        XCTAssertEqual(entries[1].result, .correct)
    }

    func test_未回答時のスコアボードはホストから入室順に戻る() {
        let players = [
            RoomState.Player(id: "guest", nickname: "参加者", score: 0, joinedAtMS: 10),
            RoomState.Player(id: "host", nickname: "ホスト", score: 0, joinedAtMS: 30),
            RoomState.Player(id: "later", nickname: "後から", score: 0, joinedAtMS: 20)
        ]

        let entries = BattleScoreBoard.entries(
            players: players,
            hostID: "host",
            answers: [],
            failedIDs: [],
            correctIDs: []
        )

        XCTAssertEqual(entries.map(\.id), ["host", "guest", "later"])
        XCTAssertEqual(entries.map(\.answerRank), [nil, nil, nil])
        XCTAssertTrue(entries.allSatisfy { $0.result == nil })
    }

    // MARK: - CPU人数・強さの頑健性

    func test_CPUの人数と強さを変えてもクラッシュせず完走する() async {
        for cpuCount in [0, 1, 3, 99] {
            let timer = ManualTimer()
            let session = makeSession(cpuCount: cpuCount, strategy: aggressiveCPU, timer: timer)
            await session.startGame(questions: makeQuestions(count: 2))

            timer.fireAll() // CPUの回答・発表・次問をすべて発火し、最後まで進める

            XCTAssertEqual(session.state?.status, .finished, "cpuCount=\(cpuCount)")
            XCTAssertEqual(session.state?.players.count, min(CPUProfile.roster.count, max(1, cpuCount)) + 1)
        }
    }
}
