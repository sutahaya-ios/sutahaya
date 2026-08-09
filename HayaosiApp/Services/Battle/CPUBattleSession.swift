import Foundation
import Observation
import SwiftData

/// ローカルで完結するCPU対戦(Firebase不要)。
/// オンライン対戦と同じ RoomState を組み立てて同じ画面を駆動する。UI開発・一人練習用。
///
/// 責務はセッション状態・試合進行・採点まで。**CPUが「いつ・何を答えるか」の判断は
/// `CPUAnswerStrategy`(純粋計算)に分離**してある。進行・採点は private な状態遷移
/// そのものなので、アクセス制御を弱めないためにこのファイルに残す
@MainActor
@Observable
final class CPUBattleSession: BattleSession {
    /// タイマーの生成方法。テストでは即時・手動発火の実装に差し替える(既定は実時間で待つ)
    typealias TimerScheduler = @MainActor (_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never>

    let myID = "me"
    let isHost = true
    let isOnline = false
    private(set) var state: RoomState?

    private let nickname: String
    private let settings: RoomState.Settings
    private let cpus: [CPUProfile]
    private let strategy: CPUAnswerStrategy
    private let makeTimer: TimerScheduler

    private var scores: [String: Int] = [:]
    private var questionPayloads: [RoomState.QuestionPayload] = []
    private var status: RoomState.Status = .waiting

    // 進行中の問題の状態
    private var questionIndex = 0
    private var phase: RoomState.GamePhase = .question
    private var startDelayMS: Double = 0
    private var startedAtMS: Double = 0
    private var failedIDs: Set<String> = []
    private var answers: [RoomState.Answer] = []
    private var reveal: RoomState.Reveal?
    /// この問題で実際に回答しうる参加者。参加を見送ったCPUは待っても答えないので除く
    private var activeIDs: Set<String> = []
    /// この問題を始めた時点の得点。回答のたびに「この値+確定した増減」へ置き直す
    private var scoresAtQuestionStart: [String: Int] = [:]
    /// 回答受付の世代。仕切り直しごとに進め、古い予約タスクを無効化する
    private var answerRound = 0

    private var myResults: [String: Bool] = [:]
    private var hasSavedResults = false
    private var pendingTasks: [Task<Void, Never>] = []

    /// `strategy`・`timerScheduler` はテスト用の注入口。本番は既定値のまま使う
    init(nickname: String,
         settings: RoomState.Settings,
         cpuCount: Int,
         strategy: CPUAnswerStrategy = CPUAnswerStrategy(),
         timerScheduler: TimerScheduler? = nil) {
        self.nickname = nickname
        self.settings = settings
        self.cpus = Array(CPUProfile.roster.prefix(max(1, cpuCount)))
        self.strategy = strategy
        self.makeTimer = timerScheduler ?? { seconds, action in
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                action()
            }
        }
        publish()
    }

    // MARK: - BattleSession

    func startGame(questions: [Question]) async {
        guard status == .waiting, !questions.isEmpty else { return }
        questionPayloads = questions.map {
            RoomState.QuestionPayload(id: $0.id, text: $0.text, choices: $0.choices.shuffled(), answer: $0.answer)
        }
        status = .playing
        beginQuestion(0)
    }

    func rematch() async {
        guard status == .finished else { return }
        cancelAllTasks()
        scores = [:]
        myResults = [:]
        hasSavedResults = false
        questionPayloads = []
        questionIndex = 0
        phase = .question
        startDelayMS = 0
        failedIDs = []
        answers = []
        reveal = nil
        activeIDs = []
        scoresAtQuestionStart = [:]
        status = .waiting
        publish()
    }

    func submitAnswer(_ choice: String, visibleCount: Int) {
        evaluate(uid: myID, choice: choice, visibleCount: visibleCount, round: answerRound)
    }

    func leave() {
        cancelAllTasks()
    }

    /// CPU対戦は一人練習扱いで学習履歴・復習リストに反映する
    func saveResultsIfNeeded(context: ModelContext) {
        guard !hasSavedResults, status == .finished else { return }
        hasSavedResults = true
        ResultRecorder.record(
            results: myResults.map { ($0.key, $0.value) },
            mode: .practice,
            context: context
        )
    }

    // MARK: - 進行(オンライン版のホストエンジンと同じルール)

    private func beginQuestion(_ index: Int) {
        questionIndex = index
        phase = .question
        startDelayMS = index == 0 ? BattleRules.matchStartDelayMS : 0
        startedAtMS = Date().timeIntervalSince1970 * 1000
        failedIDs = []
        answers = []
        reveal = nil
        scoresAtQuestionStart = scores
        answerRound += 1
        publish()
        openAnswering()
    }

    /// 問題開始後、CPUの回答と問題の制限時間を予約する
    private func openAnswering() {
        let currentRound = answerRound
        let startDelay = startDelayMS / 1_000
        let participatingCPUs = cpus.filter { strategy.participates($0) }
        // 参加を見送ったCPUは最後まで答えないので、待たずに発表へ進めるよう対象から外す
        activeIDs = Set([myID] + participatingCPUs.map(\.id))
        for cpu in participatingCPUs {
            scheduleCPUAction(cpu: cpu, round: currentRound, startDelay: startDelay)
        }
        schedule(after: startDelay + settings.timeLimit) { [weak self] in
            self?.timeoutQuestion(round: currentRound)
        }
    }

    /// CPUの動き。いつ・何を答えるかの判断は `CPUAnswerStrategy` が決める
    private func scheduleCPUAction(cpu: CPUProfile, round: Int, startDelay: TimeInterval) {
        let question = questionPayloads[questionIndex]
        let plan = strategy.progressivePlan(for: cpu, question: question, timeLimit: settings.timeLimit)
        schedule(after: startDelay + plan.delay) { [weak self] in
            self?.evaluate(uid: cpu.id, choice: plan.choice, visibleCount: plan.visibleCount, round: round)
        }
    }

    // MARK: - 採点

    /// 回答を記録し、その時点で確定した得点をすぐ反映する(残りの回答を待つ間も結果が見える)
    private func evaluate(uid: String, choice: String, visibleCount: Int, round: Int) {
        guard status == .playing, phase == .question, round == answerRound,
              questionPayloads.indices.contains(questionIndex),
              canAnswer(uid: uid) else { return }

        let question = questionPayloads[questionIndex]
        let isCorrect = choice == question.answer
        answers.append(RoomState.Answer(
            uid: uid,
            choice: choice,
            answeredAtMS: Date().timeIntervalSince1970 * 1000,
            visibleCount: visibleCount
        ))
        if uid == myID {
            myResults[question.id] = isCorrect
        }

        if !isCorrect {
            failedIDs.insert(uid)
        }
        applyScoring(for: question)
        publish()

        // 回答しうる全員が使い切ったら、制限時間を待たずに発表へ進む
        if hasEveryoneAnswered {
            finishQuestion(round: round)
        }
    }

    /// いま届いている回答だけで採点し、問題開始時の得点へ上書きする。
    /// 毎回ゼロから計算し直すので、後から順位が入れ替わっても二重加算にならない
    @discardableResult
    private func applyScoring(for question: RoomState.QuestionPayload) -> BattleScoring.Result {
        let scoring = BattleScoring.result(
            answers: answers,
            correctAnswer: question.answer,
            participantIDs: participantIDs
        )
        scores = scoresAtQuestionStart
        for (uid, pointChange) in scoring.pointChanges {
            scores[uid, default: 0] += pointChange
        }
        return scoring
    }

    /// この問題にまだ回答できるか(未回答かつ誤答していない)
    private func canAnswer(uid: String) -> Bool {
        guard !failedIDs.contains(uid) else { return false }
        return !answers.contains { $0.uid == uid }
    }

    private var participantIDs: [String] { [myID] + cpus.map(\.id) }

    /// 回答しうる参加者が全員1回ずつ回答を終えたか(正誤は問わない)
    private var hasEveryoneAnswered: Bool {
        let answeredIDs = Set(answers.map(\.uid))
        return activeIDs.allSatisfy(answeredIDs.contains)
    }

    private func timeoutQuestion(round: Int) {
        finishQuestion(round: round)
    }

    /// 最終的な採点を確定して発表へ進む。制限時間切れと「全員が回答済み」の両方から呼ばれる。
    /// 得点は回答のたびに反映済みだが、無回答者を含めた確定値をここで置き直す
    private func finishQuestion(round: Int) {
        guard status == .playing, phase == .question, round == answerRound,
              questionPayloads.indices.contains(questionIndex) else { return }
        let question = questionPayloads[questionIndex]
        let scoring = applyScoring(for: question)
        showReveal(RoomState.Reveal(correctAnswer: question.answer, correctIDs: scoring.correctIDs))
    }

    private func showReveal(_ newReveal: RoomState.Reveal) {
        phase = .reveal
        reveal = newReveal
        publish()
        let index = questionIndex
        schedule(after: BattleRules.revealDuration) { [weak self] in
            self?.advance(from: index)
        }
    }

    private func advance(from index: Int) {
        guard status == .playing, phase == .reveal, questionIndex == index else { return }
        if index + 1 < questionPayloads.count {
            beginQuestion(index + 1)
        } else {
            status = .finished
            publish()
        }
    }

    // MARK: - 状態の公開・タスク管理

    private func publish() {
        let players = ([(myID, nickname)] + cpus.map { ($0.id, $0.nickname) })
            .enumerated()
            .map { index, entry in
                RoomState.Player(id: entry.0, nickname: entry.1, score: scores[entry.0] ?? 0, joinedAtMS: Double(index))
            }

        var game: RoomState.Game?
        if status == .playing || status == .finished {
            game = RoomState.Game(
                questionIndex: questionIndex,
                phase: status == .finished ? .finished : phase,
                startDelayMS: startDelayMS,
                startedAtMS: startedAtMS,
                failedIDs: failedIDs,
                answers: answers,
                reveal: reveal
            )
        }

        state = RoomState(
            code: "BOT",
            hostID: myID,
            status: status,
            settings: settings,
            players: players,
            questions: questionPayloads,
            game: game
        )
    }

    private func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        pendingTasks.append(makeTimer(seconds, action))
    }

    private func cancelAllTasks() {
        pendingTasks.forEach { $0.cancel() }
        pendingTasks = []
    }
}
