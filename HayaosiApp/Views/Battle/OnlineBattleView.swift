import SwiftUI

/// 対戦画面:問題表示・早押しボタン・回答UI・スコア表示(要件 §9-5)
struct OnlineBattleView: View {
    private static let tickInterval: TimeInterval = 0.1

    let session: any BattleSession

    @State private var submittedChoice: String?

    var body: some View {
        VStack(spacing: 16) {
            scoreBoard

            if let state = session.state, let game = state.game,
               let question = session.currentQuestion {
                progressHeader(state: state, game: game)

                Spacer()

                BattleQuestionText(
                    text: question.text,
                    style: state.settings.style,
                    mode: revealMode(state: state, game: game)
                )
                // 問題が変わったことを分かるように入れ替える
                .id(game.questionIndex)
                .transition(.opacity.combined(with: .move(edge: .top)))

                Spacer()

                interactionArea(state: state, game: game, question: question)
                    .animation(BattleAnimation.reveal, value: game.phase)
                    .animation(BattleAnimation.reveal, value: game.buzzWinner)
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
        .onAppear {
            SoundPlayer.shared.play(.questionStart)
        }
        .onChange(of: session.state?.game?.questionIndex) { _, _ in
            submittedChoice = nil
            SoundPlayer.shared.play(.questionStart)
        }
        .onChange(of: session.state?.game?.buzzWinner) { _, newWinner in
            if newWinner != nil {
                SoundPlayer.shared.play(.buzz)
            }
        }
        .onChange(of: session.state?.game?.failedIDs.count) { oldCount, newCount in
            if let oldCount, let newCount, newCount > oldCount {
                SoundPlayer.shared.play(.wrong)
            }
        }
        .onChange(of: session.state?.game?.reveal) { _, newReveal in
            if let newReveal {
                SoundPlayer.shared.play(newReveal.byTimeout ? .timeUp : .correct)
            }
        }
    }

    /// 文字送りは「まだ誰も押していない間」だけ進める。
    /// 誰かが押した後は全文を出す(回答者が読めないと答えられず、
    /// 回答権が移った人も問題文を読み直せる必要があるため)
    private func revealMode(state: RoomState, game: RoomState.Game) -> BattleQuestionText.Mode {
        let hasBuzzed = game.buzzWinner != nil || !game.failedIDs.isEmpty
        guard game.phase == .question, !hasBuzzed else { return .full }
        return .progressing(startedAtMS: game.startedAtMS, timeLimit: state.settings.timeLimit)
    }

    // MARK: - スコア・進行表示

    private var scoreBoard: some View {
        BattleScoreBoard(
            players: session.state?.players ?? [],
            myID: session.myID,
            scorerID: scorerID
        )
    }

    /// 発表中だけ、得点したプレイヤーを強調するために返す
    private var scorerID: String? {
        guard let game = session.state?.game, game.phase == .reveal,
              let reveal = game.reveal, !reveal.byTimeout else { return nil }
        return reveal.scorerID
    }

    private func progressHeader(state: RoomState, game: RoomState.Game) -> some View {
        TimelineView(.periodic(from: .now, by: Self.tickInterval)) { timeline in
            let isBuzzOpen = game.buzzWinner == nil && game.phase == .question
            BattleProgressHeader(
                questionNumber: game.questionIndex + 1,
                totalCount: state.questions.count,
                remaining: isBuzzOpen ? session.remainingTime(at: timeline.date) : nil,
                timeLimit: state.settings.timeLimit
            )
        }
    }

    // MARK: - 操作エリア(状況に応じて早押し/回答/待機を出し分け)

    @ViewBuilder
    private func interactionArea(state: RoomState, game: RoomState.Game, question: RoomState.QuestionPayload) -> some View {
        if game.phase == .reveal, let reveal = game.reveal {
            BattleRevealCard(reveal: reveal, scorerName: session.player(for: reveal.scorerID)?.nickname)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if game.buzzWinner == session.myID {
            answerArea(question: question)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let winner = game.buzzWinner {
            statusLabel(
                "\(session.player(for: winner)?.nickname ?? "?")が回答中…",
                systemImage: "lock.fill",
                color: .secondary
            )
        } else if game.failedIDs.contains(session.myID) {
            statusLabel("お手つき!この問題には回答できません", systemImage: "hand.raised.fill", color: .red)
        } else {
            BuzzButton {
                Haptics.impact(.heavy)
                session.buzz()
            }
            .padding(.bottom, 24)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
            .padding(.bottom, 40)
    }

    private func answerArea(question: RoomState.QuestionPayload) -> some View {
        VStack(spacing: 12) {
            Text("回答権ゲット!\(Int(BattleRules.answerTimeLimit))秒以内に回答")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            ForEach(question.choices, id: \.self) { choice in
                Button {
                    Haptics.impact(.light)
                    submittedChoice = choice
                    session.submitAnswer(choice)
                } label: {
                    Text(choice)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(submittedChoice == choice ? .orange : .accentColor)
                .disabled(submittedChoice != nil)
            }
        }
    }
}
