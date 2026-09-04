import SwiftUI

/// 対戦画面:問題表示・早押しボタン・回答UI・スコア表示(要件 §9-5)
struct BattleView: View {
    /// 文字送りの更新間隔
    private static let tickInterval: TimeInterval = 0.1
    private static let wrongFeedbackDuration: TimeInterval = 1.2

    let session: any BattleSession

    @State private var pendingAnswer: PendingAnswer?
    @State private var isAwaitingHostResult = false
    @State private var answerErrorMessage: String?
    @State private var wrongFeedbackQuestionIndex: Int?
    @State private var wrongFeedbackTask: Task<Void, Never>?
    @State private var liveScoreBase: LiveScoreBase?

    var body: some View {
        VStack(spacing: 16) {
            scoreBoard

            if let state = session.state, let game = state.game,
               let question = session.currentQuestion {
                progressHeader(state: state, game: game)

                Spacer()

                BattleQuestionText(
                    text: question.text,
                    mode: revealMode(game: game)
                )
                // 問題が変わったことを分かるように入れ替える
                .id(game.questionIndex)
                .transition(.opacity.combined(with: .move(edge: .top)))

                Spacer()

                interactionArea(game: game, question: question)
                    .animation(BattleAnimation.reveal, value: game.phase)
            } else {
                Spacer()
                ProgressView("問題を読み込み中…")
                Spacer()
            }
        }
        .padding()
        .navigationTitle("対戦")
        .navigationBarTitleDisplayMode(.inline)
        .animation(BattleAnimation.reveal, value: session.state?.game?.questionIndex)
        .overlay {
            if wrongFeedbackQuestionIndex == session.state?.game?.questionIndex {
                WrongAnswerFeedback()
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onAppear {
            captureLiveScoreBaseIfPossible()
        }
        .onChange(of: questionKey) { _, _ in
            pendingAnswer = nil
            isAwaitingHostResult = false
            answerErrorMessage = nil
            wrongFeedbackTask?.cancel()
            wrongFeedbackQuestionIndex = nil
            captureLiveScoreBaseIfPossible(replacingExisting: true)
        }
        .onChange(of: failedIDs) { oldIDs, newIDs in
            if !newIDs.subtracting(oldIDs).isEmpty {
                SoundPlayer.shared.play(.wrong)
            }
            if !oldIDs.contains(session.myID), newIDs.contains(session.myID),
               let questionIndex = session.state?.game?.questionIndex {
                pendingAnswer = nil
                isAwaitingHostResult = false
                showWrongFeedback(for: questionIndex)
            }
        }
        .onChange(of: myAnswerChoice) { _, newChoice in
            if newChoice != nil {
                pendingAnswer = nil
                isAwaitingHostResult = false
                answerErrorMessage = nil
            }
        }
        // 正解も回答した時点で鳴らす。発表まで待たせると手応えが遅れて伝わるため
        .onChange(of: correctIDs.count) { oldCount, newCount in
            if newCount > oldCount {
                SoundPlayer.shared.play(.correct)
            }
        }
        // 正解の音は回答時に鳴らし終えているので、発表では誰も取れなかった時だけ鳴らす
        .onChange(of: session.state?.game?.reveal) { _, newReveal in
            if let newReveal, newReveal.correctIDs.isEmpty {
                SoundPlayer.shared.play(.timeUp)
            }
        }
        .onDisappear {
            wrongFeedbackTask?.cancel()
        }
    }

    /// 出題中は文字送りを進め、発表に入ったら全文を出す
    private func revealMode(game: RoomState.Game) -> BattleQuestionText.Mode {
        guard game.phase == .question else { return .full }
        return .progressing(
            startedAtMS: session.localTimeMS(forBattleTimeMS: game.effectiveStartedAtMS)
        )
    }

    // MARK: - スコア・進行表示

    private var scoreBoard: some View {
        BattleScoreBoard(
            players: session.state?.players ?? [],
            hostID: session.state?.hostID ?? session.myID,
            answers: answersForDisplay,
            failedIDs: failedIDs,
            correctIDs: correctIDs
        )
    }

    /// 最終結果の確定書き込み中は順位を出さない。確定後も締切内のaccepted回答だけを表示する。
    private var answersForDisplay: [RoomState.Answer] {
        guard let state = session.state, let game = state.game else { return [] }
        let confirmed = BattleAnswerAcceptance.confirmedAnswers(
            in: game,
            timeLimit: state.settings.timeLimit,
            participantIDs: state.players.map(\.id)
        )
        guard game.phase == .question else { return confirmed }
        guard let question = session.currentQuestion,
              let liveScoreBase,
              liveScoreBase.key == questionKey else {
            return []
        }
        let currentScores = Dictionary(
            uniqueKeysWithValues: state.players.map { ($0.id, $0.score) }
        )
        let scoresAreReflected = BattleAnswerAcceptance.scoresMatch(
            answers: confirmed,
            correctAnswer: question.answer,
            participantIDs: state.players.map(\.id),
            baseScores: liveScoreBase.scores,
            currentScores: currentScores
        )
        return scoresAreReflected ? confirmed : []
    }

    /// 問題開始時点の得点を保存する。途中参加・再接続で既に回答がある場合は、
    /// 基準点を推測せず、その問題の順位を発表確定まで隠す。
    private func captureLiveScoreBaseIfPossible(replacingExisting: Bool = false) {
        guard (replacingExisting || liveScoreBase == nil),
              let state = session.state,
              let game = state.game,
              game.phase == .question,
              let questionKey else {
            return
        }
        let accepted = BattleAnswerAcceptance.acceptedAnswers(
            in: game,
            timeLimit: state.settings.timeLimit,
            participantIDs: state.players.map(\.id)
        )
        guard accepted.isEmpty else { return }
        liveScoreBase = LiveScoreBase(
            key: questionKey,
            scores: Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, $0.score) })
        )
    }

    /// 誤答済みのプレイヤー。発表中も残して、その問題の結果を確認できるようにする
    private var failedIDs: Set<String> {
        guard let game = session.state?.game else { return [] }
        return game.failedIDs.intersection(Set(answersForDisplay.map(\.uid)))
    }

    private var questionKey: QuestionKey? {
        guard let game = session.state?.game else { return nil }
        return QuestionKey(index: game.questionIndex, startedAtMS: game.effectiveStartedAtMS)
    }

    private var myAnswerChoice: String? {
        guard let game = session.state?.game else { return nil }
        return myAnswer(in: game)?.choice
    }

    /// 正解者。出題中も、届いた回答から確定したぶんはその場で見せる
    /// (得点が同時に動くので、正誤だけ伏せても意味がないため)
    private var correctIDs: Set<String> {
        guard let game = session.state?.game else { return [] }
        if game.phase == .reveal, let reveal = game.reveal {
            return Set(reveal.correctIDs).intersection(Set(answersForDisplay.map(\.uid)))
        }
        guard let question = session.currentQuestion else { return [] }
        return Set(answersForDisplay.filter { $0.choice == question.answer }.map(\.uid))
    }

    private func progressHeader(state: RoomState, game: RoomState.Game) -> some View {
        // 残り時間バーは段差が見えるため、画面のリフレッシュレートに合わせて引き直す
        TimelineView(.animation) { timeline in
            BattleProgressHeader(
                questionNumber: game.questionIndex + 1,
                totalCount: state.questions.count,
                remaining: game.phase == .question ? session.remainingTime(at: timeline.date) : nil,
                timeLimit: state.settings.timeLimit
            )
        }
    }

    // MARK: - 操作エリア

    @ViewBuilder
    private func interactionArea(game: RoomState.Game, question: RoomState.QuestionPayload) -> some View {
        if game.phase == .reveal {
            if let reveal = game.reveal {
                BattleRevealCard(
                    reveal: reveal,
                    correctNames: reveal.correctIDs.compactMap { displayName(for: $0) }
                )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                ProgressView("結果を確定中…")
            }
        } else {
            progressiveChoiceArea(game: game, question: question)
        }
    }

    /// 文字送り型の操作エリア。4択は最初から出ていて、押した瞬間が回答になる
    private func progressiveChoiceArea(game: RoomState.Game, question: RoomState.QuestionPayload) -> some View {
        VStack(spacing: 10) {
            if let answerErrorMessage {
                Label(answerErrorMessage, systemImage: "wifi.exclamationmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            } else if game.failedIDs.contains(session.myID) {
                Label("お手つき!この問題には回答できません", systemImage: "hand.raised.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            } else if let mine = myAnswer(in: game) {
                Label("回答しました(\(mine.visibleCount)文字目)", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            } else if pendingAnswer?.questionIndex == game.questionIndex {
                Label {
                    if isAwaitingHostResult {
                        Text("ホストの判定を待っています…")
                    } else {
                        // 送信中stateと表示領域は維持し、瞬間的な文言だけ見せない。
                        Text("回答を送信中…")
                            .hidden()
                    }
                } icon: {
                    Image(systemName: isAwaitingHostResult ? "hourglass" : "arrow.up.circle")
                }
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            // 回答権はFirebase補正時刻で短周期に再評価し、
            // 相手の回答更新を待たずに開始時刻を跨げるようにする。
            TimelineView(.periodic(from: .now, by: Self.tickInterval)) { timeline in
                BattleChoiceList(
                    choices: question.choices,
                    myChoice: myAnswer(in: game)?.choice ?? pendingAnswer?.choice,
                    canAnswer: session.canAnswer(at: timeline.date) && pendingAnswer == nil
                ) { choice in
                    Haptics.impact(.heavy)
                    let pending = PendingAnswer(questionIndex: game.questionIndex, choice: choice)
                    pendingAnswer = pending
                    isAwaitingHostResult = false
                    answerErrorMessage = nil
                    session.submitAnswer(
                        choice,
                        visibleCount: session.visibleCharacterCount(at: .now)
                    ) { outcome in
                        guard pendingAnswer == pending else { return }
                        switch outcome {
                        case .accepted:
                            pendingAnswer = nil
                            isAwaitingHostResult = false
                        case .awaitingHostResult:
                            isAwaitingHostResult = true
                        case .rejected:
                            pendingAnswer = nil
                            isAwaitingHostResult = false
                            if questionKey?.index == pending.questionIndex {
                                answerErrorMessage = "制限時間を過ぎたか、通信により回答が受理されませんでした"
                            }
                        }
                    }
                }
            }
        }
    }

    private func myAnswer(in game: RoomState.Game) -> RoomState.Answer? {
        answersForDisplay.first { $0.uid == session.myID }
    }

    private func displayName(for playerID: String?) -> String? {
        session.player(for: playerID)?.nickname
    }

    private func showWrongFeedback(for questionIndex: Int) {
        wrongFeedbackTask?.cancel()
        withAnimation(BattleAnimation.reveal) {
            wrongFeedbackQuestionIndex = questionIndex
        }
        wrongFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(Self.wrongFeedbackDuration))
            guard !Task.isCancelled else { return }
            withAnimation(BattleAnimation.reveal) {
                wrongFeedbackQuestionIndex = nil
            }
        }
    }

}

private struct PendingAnswer: Equatable {
    let questionIndex: Int
    let choice: String
}

private struct QuestionKey: Equatable {
    let index: Int
    let startedAtMS: Double
}

private struct LiveScoreBase {
    let key: QuestionKey
    let scores: [String: Int]
}

private struct WrongAnswerFeedback: View {
    var body: some View {
        Label("不正解", systemImage: "xmark.circle.fill")
            .font(.title.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 8)
            .accessibilityLabel("不正解")
    }
}
