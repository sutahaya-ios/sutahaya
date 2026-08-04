import Foundation
import Observation
import SwiftData

/// ローカルで完結するボット対戦(Firebase不要)。
/// オンライン対戦と同じ RoomState を組み立てて同じ画面を駆動する。UI開発・一人練習用
@MainActor
@Observable
final class BotBattleSession: BattleSession {
    private struct BotProfile {
        let id: String
        let nickname: String
        /// 問題ごとに早押しに参加する確率
        let buzzProbability: Double
        /// 回答が正解になる確率
        let correctProbability: Double
        /// 問題文が全部見えている場合に、早押しするまでの待ち時間(秒)
        let buzzDelay: ClosedRange<Double>
        /// 文字送り型で、問題文がどこまで表示されたら押すか(0〜1)。
        /// 秒で固定すると表示量に関係なく押してしまい、人間が読む前に取られてしまうため割合で持つ
        let buzzRevealFraction: ClosedRange<Double>
    }

    /// 先頭から botCount 体が参加する(1体なら「中」だけ)
    private static let botProfiles = [
        BotProfile(id: "bot-normal", nickname: "ボット(中)", buzzProbability: 0.9, correctProbability: 0.55,
                   buzzDelay: 2.0...7.0, buzzRevealFraction: 0.5...0.85),
        BotProfile(id: "bot-strong", nickname: "ボット(強)", buzzProbability: 0.95, correctProbability: 0.75,
                   buzzDelay: 1.2...5.0, buzzRevealFraction: 0.35...0.7),
        BotProfile(id: "bot-weak", nickname: "ボット(弱)", buzzProbability: 0.7, correctProbability: 0.35,
                   buzzDelay: 3.0...9.0, buzzRevealFraction: 0.7...1.0)
    ]
    private static let botAnswerDelay: ClosedRange<Double> = 1.0...2.5
    /// 制限時間ぎりぎりの押下は不自然なので、ボットは制限時間の8割までに押す
    private static let botBuzzDeadlineRatio = 0.8

    let myID = "me"
    let isHost = true
    let isOnline = false
    private(set) var state: RoomState?

    private let nickname: String
    private let settings: RoomState.Settings
    private let bots: [BotProfile]

    private var scores: [String: Int] = [:]
    private var questionPayloads: [RoomState.QuestionPayload] = []
    private var status: RoomState.Status = .waiting

    // 進行中の問題の状態
    private var questionIndex = 0
    private var phase: RoomState.GamePhase = .question
    private var startedAtMS: Double = 0
    private var buzzWinner: String?
    private var failedIDs: Set<String> = []
    private var reveal: RoomState.Reveal?
    /// 早押し受付の世代。仕切り直しごとに進め、古い予約タスクを無効化する
    private var buzzRound = 0

    private var myResults: [String: Bool] = [:]
    private var hasSavedResults = false
    private var pendingTasks: [Task<Void, Never>] = []

    init(nickname: String, settings: RoomState.Settings, botCount: Int) {
        self.nickname = nickname
        self.settings = settings
        self.bots = Array(Self.botProfiles.prefix(max(1, botCount)))
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
        reveal = nil
        status = .waiting
        publish()
    }

    func buzz() {
        attemptBuzz(as: myID, round: buzzRound)
    }

    func submitAnswer(_ choice: String) {
        evaluate(uid: myID, choice: choice, round: buzzRound)
    }

    func leave() {
        cancelAllTasks()
    }

    /// ボット対戦は一人練習扱いで学習履歴・復習リストに反映する
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
        reveal = nil
        buzzRound += 1
        publish()
        openBuzzing()
    }

    /// 早押し受付を開始する(問題開始時と、誤答での仕切り直し時)
    private func openBuzzing() {
        let round = buzzRound
        for bot in bots where !failedIDs.contains(bot.id) && Double.random(in: 0...1) < bot.buzzProbability {
            schedule(after: buzzDelay(for: bot)) { [weak self] in
                self?.attemptBuzz(as: bot.id, round: round)
            }
        }
        schedule(after: settings.timeLimit) { [weak self] in
            self?.timeoutQuestion(round: round)
        }
    }

    /// ボットが押すまでの待ち時間。
    /// 文字送り中は「問題文をどこまで読んだか」を基準にし、全文が見えている場合は反射勝負として秒で決める
    private func buzzDelay(for bot: BotProfile) -> TimeInterval {
        let base: TimeInterval
        if isQuestionFullyRevealed {
            base = Double.random(in: bot.buzzDelay)
        } else {
            base = ProgressiveReveal.time(
                forVisibleFraction: Double.random(in: bot.buzzRevealFraction),
                timeLimit: settings.timeLimit
            )
        }
        // 制限時間ぎりぎりの押下は不自然なので上限を設ける
        return min(base, settings.timeLimit * Self.botBuzzDeadlineRatio)
    }

    /// 問題文が最初から全部見えているか。
    /// 速答型は常に全文。文字送り型でも誰かが一度押した後は全文表示になる(`OnlineBattleView` と同じ判定)
    private var isQuestionFullyRevealed: Bool {
        !settings.style.revealsProgressively || !failedIDs.isEmpty
    }

    /// 最初に押した1人に回答権を与える
    private func attemptBuzz(as id: String, round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == nil, round == buzzRound,
              !failedIDs.contains(id) else { return }
        buzzWinner = id
        publish()

        if let bot = bots.first(where: { $0.id == id }) {
            scheduleBotAnswer(bot: bot, round: round)
        }
        schedule(after: BattleRules.answerTimeLimit) { [weak self] in
            self?.timeoutAnswer(winner: id, round: round)
        }
    }

    private func scheduleBotAnswer(bot: BotProfile, round: Int) {
        let question = questionPayloads[questionIndex]
        let choice: String
        if Double.random(in: 0...1) < bot.correctProbability {
            choice = question.answer
        } else {
            choice = question.choices.filter { $0 != question.answer }.randomElement() ?? question.answer
        }
        schedule(after: Double.random(in: Self.botAnswerDelay)) { [weak self] in
            self?.evaluate(uid: bot.id, choice: choice, round: round)
        }
    }

    /// 採点:正解+1でリザルト発表、誤答−1で仕切り直し(要件 §5.1.2)
    private func evaluate(uid: String, choice: String, round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == uid, round == buzzRound,
              questionPayloads.indices.contains(questionIndex) else { return }

        let question = questionPayloads[questionIndex]
        let isCorrect = choice == question.answer
        scores[uid, default: 0] += isCorrect ? BattleRules.correctPoint : BattleRules.wrongPoint
        if uid == myID {
            myResults[question.id] = isCorrect
        }

        if isCorrect {
            showReveal(RoomState.Reveal(correctAnswer: question.answer, scorerID: uid, byTimeout: false))
        } else {
            failedIDs.insert(uid)
            buzzWinner = nil
            startedAtMS = Date().timeIntervalSince1970 * 1000
            buzzRound += 1
            publish()
            openBuzzing()
        }
    }

    /// 回答権を持ったまま時間切れ → 誤答扱い
    private func timeoutAnswer(winner: String, round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == winner, round == buzzRound else { return }
        evaluate(uid: winner, choice: "", round: round)
    }

    /// 誰も押さずに時間切れ → 問題が流れる
    private func timeoutQuestion(round: Int) {
        guard status == .playing, phase == .question,
              buzzWinner == nil, round == buzzRound,
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
        let players = ([(myID, nickname)] + bots.map { ($0.id, $0.nickname) })
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
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        pendingTasks.append(task)
    }

    private func cancelAllTasks() {
        pendingTasks.forEach { $0.cancel() }
        pendingTasks = []
    }
}
