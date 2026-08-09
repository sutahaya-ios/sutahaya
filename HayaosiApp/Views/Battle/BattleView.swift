import SwiftUI

/// 対戦画面:問題表示・早押しボタン・回答UI・スコア表示(要件 §9-5)
struct BattleView: View {
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
        .onAppear {
            SoundPlayer.shared.play(.questionStart)
        }
        .onChange(of: session.state?.game?.questionIndex) { _, _ in
            submittedChoice = nil
            SoundPlayer.shared.play(.questionStart)
        }
        .onChange(of: session.state?.game?.failedIDs.count) { oldCount, newCount in
            if let oldCount, let newCount, newCount > oldCount {
                SoundPlayer.shared.play(.wrong)
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
    }

    /// 出題中は文字送りを進め、発表に入ったら全文を出す
    private func revealMode(game: RoomState.Game) -> BattleQuestionText.Mode {
        guard game.phase == .question else { return .full }
        return .progressing(startedAtMS: game.effectiveStartedAtMS)
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
            if game.failedIDs.contains(session.myID) {
                Label("お手つき!この問題には回答できません", systemImage: "hand.raised.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            } else if let mine = myAnswer(in: game) {
                Label("回答しました(\(mine.visibleCount)文字目)", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            BattleChoiceList(
                choices: question.choices,
                myChoice: myAnswer(in: game)?.choice ?? submittedChoice,
                canAnswer: session.canAnswerNow && submittedChoice == nil
            ) { choice in
                Haptics.impact(.heavy)
                submittedChoice = choice
                session.submitAnswer(choice, visibleCount: session.visibleCharacterCount(at: .now))
            }
        }
    }

    private func myAnswer(in game: RoomState.Game) -> RoomState.Answer? {
        game.answers.first { $0.uid == session.myID }
    }

    private func displayName(for playerID: String?) -> String? {
        session.player(for: playerID)?.nickname
    }

}
