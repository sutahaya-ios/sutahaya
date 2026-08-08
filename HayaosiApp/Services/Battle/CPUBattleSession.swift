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
    private var startedAtMS: Double = 0
    private var buzzWinner: String?
    private var failedIDs: Set<String> = []
    private var answers: [RoomState.Answer] = []
    private var reveal: RoomState.Reveal?
    /// 回答受付の世代。仕切り直しごとに進め、古い予約タスクを無効化する
    private var answerRound = 0

    private var myResults: [String: Bool] = [:]
    private var hasSavedResults = false
    private var pendingTasks: [Task<Void, Never>] = []

    private var isProgressiveChoice: Bool { settings.style.revealsProgressively }

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
        buzzWinner = nil
        failedIDs = []
        answers = []
        reveal = nil
        status = .waiting
        publish()
    }

    func buzz() {
        guard !isProgressiveChoice else { return }
        attemptBuzz(as: myID, round: answerRound)
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
        startedAtMS = Date().timeIntervalSince1970 * 1000
        buzzWinner = nil
        failedIDs = []
        answers = []
        reveal = nil
        answerRound += 1
        publish()
        openAnswering()
    }

    /// 回答受付を開始する(問題開始時と、即答型で誤答による仕切り直し時)
    private func openAnswering() {
        let currentRound = answerRound
        for cpu in cpus where !failedIDs.contains(cpu.id)
            && !answers.contains(where: { $0.uid == cpu.id })
            && strategy.participates(cpu) {
            scheduleCPUAction(cpu: cpu, round: currentRound)
        }
        schedule(after: settings.timeLimit) { [weak self] in
            self?.timeoutQuestion(round: currentRound)
        }
    }

    /// CPUの動き。いつ・何を答えるかの判断は `CPUAnswerStrategy` が決める
    private func scheduleCPUAction(cpu: CPUProfile, round: Int) {
        let question = questionPayloads[questionIndex]
        guard isProgressiveChoice else {
            let delay = strategy.buzzDelay(for: cpu, timeLimit: settings.timeLimit)
            schedule(after: delay) { [weak self] in
                self?.attemptBuzz(as: cpu.id, round: round)
            }
            return
        }

        let plan = strategy.progressivePlan(for: cpu, question: question, timeLimit: settings.timeLimit)
        schedule(after: plan.delay) { [weak self] in
            self?.evaluate(uid: cpu.id, choice: plan.choice, visibleCount: plan.visibleCount, round: round)
        }
    }

    // MARK: - 即答型:早押しボタン

    /// 最初に押した1人に回答権を与える
    private func attemptBuzz(as id: String, round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == nil, round == answerRound,
              !failedIDs.contains(id) else { return }
        buzzWinner = id
        publish()

        if let cpu = cpus.first(where: { $0.id == id }) {
            let question = questionPayloads[questionIndex]
            let plan = strategy.postBuzzPlan(for: cpu, question: question)
            let total = question.text.count
            schedule(after: plan.delay) { [weak self] in
                self?.evaluate(uid: cpu.id, choice: plan.choice, visibleCount: total, round: round)
            }
        }
        schedule(after: BattleRules.answerTimeLimit) { [weak self] in
            self?.timeoutAnswer(winner: id, round: round)
        }
    }

    // MARK: - 採点

    /// 正解+1でその問題の勝者。誤答−1で、そのプレイヤーはこの問題に再回答できない(要件 §5.1.2)
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
        scores[uid, default: 0] += isCorrect ? BattleRules.correctPoint : BattleRules.wrongPoint
        if uid == myID {
            myResults[question.id] = isCorrect
        }

        if isCorrect {
            showReveal(RoomState.Reveal(correctAnswer: question.answer, scorerID: uid, byTimeout: false))
            return
        }

        failedIDs.insert(uid)
        buzzWinner = nil
        publish()

        if everyoneFinishedAnswering {
            // 全員が答え終えて正解が出なかった。待っても何も起きないので発表へ進む
            showReveal(RoomState.Reveal(correctAnswer: question.answer, scorerID: nil, byTimeout: true))
        } else if !isProgressiveChoice {
            // 即答型は早押しからやり直す
            startedAtMS = Date().timeIntervalSince1970 * 1000
            answerRound += 1
            publish()
            openAnswering()
        }
    }

    /// この問題にまだ回答できるか(未回答かつ誤答していない)
    private func canAnswer(uid: String) -> Bool {
        guard !failedIDs.contains(uid) else { return false }
        if isProgressiveChoice {
            return !answers.contains { $0.uid == uid }
        }
        return buzzWinner == uid
    }

    private var everyoneFinishedAnswering: Bool {
        let participants = [myID] + cpus.map(\.id)
        return participants.allSatisfy { failedIDs.contains($0) }
    }

    /// 回答権を持ったまま時間切れ(即答型のみ)
    private func timeoutAnswer(winner: String, round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == winner, round == answerRound else { return }
        let total = questionPayloads.indices.contains(questionIndex)
            ? questionPayloads[questionIndex].text.count : 0
        evaluate(uid: winner, choice: "", visibleCount: total, round: round)
    }

    /// 制限時間まで誰も正解しなかった → 問題が流れる
    private func timeoutQuestion(round: Int) {
        guard status == .playing, phase == .question, round == answerRound,
              questionPayloads.indices.contains(questionIndex) else { return }
        showReveal(RoomState.Reveal(
            correctAnswer: questionPayloads[questionIndex].answer,
            scorerID: nil,
            byTimeout: true
        ))
    }

    private func showReveal(_ newReveal: RoomState.Reveal) {
        phase = .reveal
        reveal = newReveal
        buzzWinner = nil
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
                startedAtMS: startedAtMS,
                buzzWinner: buzzWinner,
                buzzQueue: [:],
                failedIDs: failedIDs,
                answer: nil,
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
