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
            settings: .init(questionCount: 10, timeLimit: 20, genre: .englishWord, style: .progressiveChoice),
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
        let session = makeSession(cpuCount: 2, timer: ManualTimer())

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

    func test_正解すると加点され勝者として発表される() async {
        let session = makeSession(timer: ManualTimer())
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 3)

        let me = session.state?.players.first { $0.id == "me" }
        XCTAssertEqual(me?.score, BattleRules.correctPoint)
        XCTAssertEqual(session.state?.game?.phase, .reveal)
        XCTAssertEqual(session.state?.game?.reveal?.scorerID, "me")
        XCTAssertEqual(session.state?.game?.answers.first?.visibleCount, 3, "何文字目で答えたかが記録される")
    }

    func test_誤答すると減点されその問題に再回答できない() async {
        let session = makeSession(timer: ManualTimer())
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer("わざと間違い", visibleCount: 2)
        session.submitAnswer(currentAnswer(session), visibleCount: 5) // ロックされているので無視されるはず

        let me = session.state?.players.first { $0.id == "me" }
        XCTAssertEqual(me?.score, BattleRules.wrongPoint)
        XCTAssertEqual(session.state?.game?.failedIDs.contains("me"), true)
        XCTAssertEqual(session.state?.game?.answers.count, 1, "2回目の回答は受け付けない")
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

    func test_正解すると次の問題へ進む() async {
        let timer = ManualTimer()
        let session = makeSession(timer: timer)
        await session.startGame(questions: makeQuestions(count: 2))

        session.submitAnswer(currentAnswer(session), visibleCount: 1)
        // この時点の予約(第1問の制限時間・発表の経過)だけを発火する。
        // 第1問の制限時間はphaseガードで無効になり、発表の経過で第2問が始まるはず
        timer.fireExisting()

        XCTAssertEqual(session.state?.status, .playing)
        XCTAssertEqual(session.state?.game?.questionIndex, 1)
        XCTAssertEqual(session.state?.game?.phase, .question)
        XCTAssertEqual(session.state?.game?.startDelayMS, 0, "開始演出は1問目の前だけ")
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

    // MARK: - CPU人数・強さの頑健性

    func test_CPUの人数と強さを変えてもクラッシュせず完走する() async {
        for cpuCount in [0, 1, 3, 99] {
            let timer = ManualTimer()
            let session = makeSession(cpuCount: cpuCount, strategy: aggressiveCPU, timer: timer)
            await session.startGame(questions: makeQuestions(count: 2))

            timer.fireAll() // CPUの回答・発表・次問をすべて発火し、最後まで進める

            XCTAssertEqual(session.state?.status, .finished, "cpuCount=\(cpuCount)")
            XCTAssertEqual(session.state?.players.count, min(3, max(1, cpuCount)) + 1)
        }
    }
}
