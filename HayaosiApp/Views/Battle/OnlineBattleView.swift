import SwiftUI

/// 対戦画面:問題表示・早押しボタン・回答UI・スコア表示(要件 §9-5)
struct OnlineBattleView: View {
    let session: any BattleSession

    @State private var submittedChoice: String?

    var body: some View {
        VStack(spacing: 16) {
            scoreBoard

            if let state = session.state, let game = state.game,
               let question = session.currentQuestion {
                progressHeader(state: state, game: game)

                Spacer()

                Text(question.text)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)

                Spacer()

                interactionArea(state: state, game: game, question: question)
            } else {
                Spacer()
                ProgressView("問題を読み込み中…")
                Spacer()
            }
        }
        .padding()
        .navigationTitle("対戦")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - スコア・進行表示

    private var scoreBoard: some View {
        HStack(spacing: 8) {
            ForEach(session.state?.players ?? []) { player in
                VStack(spacing: 4) {
                    Text(player.nickname)
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(player.score)pt")
                        .font(.headline)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(player.id == session.myID
                              ? Color.accentColor.opacity(0.15)
                              : Color(.secondarySystemBackground))
                )
            }
        }
    }

    private func progressHeader(state: RoomState, game: RoomState.Game) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("第\(game.questionIndex + 1)問 / \(state.questions.count)問")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if game.buzzWinner == nil && game.phase == .question {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    let remaining = session.remainingTime(at: timeline.date)
                    ProgressView(value: min(remaining, state.settings.timeLimit), total: state.settings.timeLimit)
                        .tint(remaining < 5 ? .red : .accentColor)
                }
            }
        }
    }

    // MARK: - 操作エリア(状況に応じて早押し/回答/待機を出し分け)

    @ViewBuilder
    private func interactionArea(state: RoomState, game: RoomState.Game, question: RoomState.QuestionPayload) -> some View {
        if game.phase == .reveal {
            revealView(state: state, game: game)
        } else if game.buzzWinner == session.myID {
            answerArea(question: question)
        } else if let winner = game.buzzWinner {
            Label("\(session.player(for: winner)?.nickname ?? "?")が回答中…", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)
        } else if game.failedIDs.contains(session.myID) {
            Label("お手つき!この問題には回答できません", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .padding(.bottom, 40)
        } else {
            buzzButton
        }
    }

    private var buzzButton: some View {
        Button {
            Haptics.impact(.heavy)
            session.buzz()
        } label: {
            Text("押す!")
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 160, height: 160)
                .background(Circle().fill(.red))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
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

    private func revealView(state: RoomState, game: RoomState.Game) -> some View {
        VStack(spacing: 12) {
            if let reveal = game.reveal {
                if reveal.byTimeout {
                    Label("時間切れ…", systemImage: "clock.badge.xmark")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if let scorer = session.player(for: reveal.scorerID) {
                    Label("\(scorer.nickname)が正解!", systemImage: "circle")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                Text("正解:\(reveal.correctAnswer)")
                    .font(.title3.bold())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.bottom, 24)
    }
}
