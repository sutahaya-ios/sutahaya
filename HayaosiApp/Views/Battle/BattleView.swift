import SwiftUI

/// 対戦画面:問題表示・早押しボタン・回答UI・スコア表示(要件 §9-5)
struct BattleView: View {
    private static let tickInterval: TimeInterval = 0.1
    private static let wrongFeedbackDuration: TimeInterval = 1.2

    let session: any BattleSession

    @State private var pendingAnswer: PendingAnswer?
    @State private var answerErrorMessage: String?
    @State private var wrongFeedbackQuestionIndex: Int?
    @State private var wrongFeedbackTask: Task<Void, Never>?

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
        .onChange(of: questionKey) { _, _ in
            pendingAnswer = nil
            answerErrorMessage = nil
            wrongFeedbackTask?.cancel()
            wrongFeedbackQuestionIndex = nil
        }
        .onChange(of: failedIDs) { oldIDs, newIDs in
            if !newIDs.subtracting(oldIDs).isEmpty {
                SoundPlayer.shared.play(.wrong)
            }
            if !oldIDs.contains(session.myID), newIDs.contains(session.myID),
               let questionIndex = session.state?.game?.questionIndex {
                pendingAnswer = nil
                showWrongFeedback(for: questionIndex)
            }
        }
        .onChange(of: myAnswerChoice) { _, newChoice in
            if newChoice != nil {
                pendingAnswer = nil
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
            answers: session.state?.game?.answers ?? [],
            failedIDs: failedIDs,
            correctIDs: correctIDs
        )
    }

    /// 誤答済みのプレイヤー。発表中も残して、その問題の結果を確認できるようにする
    private var failedIDs: Set<String> {
        session.state?.game?.failedIDs ?? []
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
            return Set(reveal.correctIDs)
        }
        guard let question = session.currentQuestion else { return [] }
        return Set(game.answers.filter { $0.choice == question.answer }.map(\.uid))
    }

    private func progressHeader(state: RoomState, game: RoomState.Game) -> some View {
        TimelineView(.periodic(from: .now, by: Self.tickInterval)) { timeline in
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
        if game.phase == .reveal, let reveal = game.reveal {
            BattleRevealCard(
                reveal: reveal,
                correctNames: reveal.correctIDs.compactMap { displayName(for: $0) }
            )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
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
                Label("回答を送信中…", systemImage: "arrow.up.circle")
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
                    answerErrorMessage = nil
                    session.submitAnswer(
                        choice,
                        visibleCount: session.visibleCharacterCount(at: .now)
                    ) { succeeded in
                        guard pendingAnswer == pending else { return }
                        if !succeeded {
                            pendingAnswer = nil
                            if questionKey?.index == pending.questionIndex {
                                answerErrorMessage = "回答を送信できませんでした。もう一度お試しください"
                            }
                        }
                    }
                }
            }
        }
    }

    private func myAnswer(in game: RoomState.Game) -> RoomState.Answer? {
        game.answers.first { $0.uid == session.myID }
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
