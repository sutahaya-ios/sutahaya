import SwiftUI

struct CompetitiveMatchContainerView: View {
    let coordinator: CompetitiveClientCoordinator

    @State private var showExitConfirmation = false

    var body: some View {
        Group {
            if let state = coordinator.battleService?.state {
                switch state.phase {
                case .created, .waitingPlayers, .countdown:
                    CompetitiveMatchSetupView(state: state)
                case .questionOpen, .questionResult, .nextQuestion:
                    CompetitiveBattleView(coordinator: coordinator, state: state)
                case .matchFinished, .settlementPending, .settled:
                    CompetitiveResultView(coordinator: coordinator, state: state)
                }
            } else {
                ProgressView("対戦を準備しています…")
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if canExitMatch {
                ToolbarItem(placement: .topBarLeading) {
                    Button(exitTitle) { showExitConfirmation = true }
                        .disabled(coordinator.isForfeitSending)
                }
            }
        }
        .confirmationDialog(
            exitDialogTitle,
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button(exitButtonTitle, role: .destructive) {
                coordinator.exitCurrentMatch()
            }
        } message: {
            Text(exitDialogMessage)
        }
    }

    private var canExitMatch: Bool {
        guard coordinator.activeSession != nil else { return false }
        guard let phase = coordinator.battleService?.state?.phase else { return true }
        return ![.matchFinished, .settlementPending, .settled].contains(phase)
    }

    private var isBeforeCommitment: Bool {
        coordinator.battleService?.state?.phase == .waitingPlayers
    }

    private var exitTitle: String { "退出" }
    private var exitButtonTitle: String { isBeforeCommitment ? "対戦を退出" : "棄権する" }
    private var exitDialogTitle: String { isBeforeCommitment ? "対戦から退出しますか？" : "対戦を棄権しますか？" }
    private var exitDialogMessage: String {
        isBeforeCommitment
            ? "COUNTDOWN前の対戦を終了します"
            : "COUNTDOWN開始後の退出は敗北として扱われます"
    }
}

private struct CompetitiveMatchSetupView: View {
    let state: CompetitivePublicState

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 155)

                if state.phase == .countdown {
                    countdown
                } else {
                    connecting
                }

                participantList
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("ランク戦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let remaining = max(
                0,
                ((state.countdownEndsAtEpochMS ?? 0) / 1_000) - timeline.date.timeIntervalSince1970
            )
            let progress = CGFloat(min(1, remaining / 3))
            VStack(spacing: 22) {
                Text("対戦開始")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.55), .indigo.opacity(0.65)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(max(1, Int(remaining.rounded(.up))))")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 104, height: 104)
            }
        }
    }

    private var connecting: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.secondary)
            Text("参加者を接続しています")
                .font(.title3.bold())
        }
    }

    private var participantList: some View {
        VStack(spacing: 8) {
            ForEach(state.participants.sorted { $0.slot < $1.slot }) { participant in
                HStack(spacing: 14) {
                    Image(systemName: participant.kind == .npc ? "cpu" : "person.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    Text(participant.displayName)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    Text(statusText(participant))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor(participant))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
        }
    }

    private func statusText(_ participant: CompetitiveParticipant) -> String {
        if participant.kind == .npc { return "NPC" }
        if participant.ready { return "準備完了" }
        if participant.joined { return "接続済み" }
        return "接続中"
    }

    private func statusColor(_ participant: CompetitiveParticipant) -> Color {
        participant.kind == .npc || participant.ready ? .green : .secondary
    }

    private var backgroundColor: Color { Color(.systemGroupedBackground) }
}

private struct CompetitiveBattleView: View {
    let coordinator: CompetitiveClientCoordinator
    let state: CompetitivePublicState

    @State private var selectedAnswerId: String?
    @State private var submittedContext: CompetitiveDisplayedQuestionContext?

    var body: some View {
        VStack(spacing: 16) {
            scoreBoard

            if let question = state.currentQuestion {
                progress(question)
                Spacer()
                QuestionTextView(text: question.prompt, mode: .full, isSingleWord: true)
                    .id(question.questionId)
                Spacer()
                if state.phase == .questionResult {
                    resultSummary(question)
                } else if state.phase == .nextQuestion {
                    ProgressView("次の問題を準備中…")
                } else {
                    answerArea(question)
                }
            } else {
                Spacer()
                ProgressView("問題を読み込み中…")
                Spacer()
            }
        }
        .padding()
        .navigationTitle("対戦")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { reconnectOverlay }
        .onChange(of: state.currentQuestion?.questionId) { _, _ in
            selectedAnswerId = nil
            submittedContext = nil
        }
    }

    private var myParticipant: CompetitiveParticipant? {
        guard let uid = coordinator.activeSession?.uid else { return nil }
        return state.participants.first { $0.uid == uid }
    }

    private var scoreBoard: some View {
        BattleScoreBoard(
            displayPlayers: state.participants.map { participant in
                let answerState = CompetitiveClientDisplay.answerState(
                    for: participant,
                    phase: state.phase,
                    result: state.questionResult
                )
                return BattleScoreBoard.DisplayPlayer(
                    id: participant.uid,
                    nickname: participant.displayName,
                    score: participant.score,
                    badge: state.phase == .questionResult
                        ? state.questionResult?.scoreDeltas[participant.uid]
                            .map(BattleScoreBoard.DisplayBadge.scoreDelta)
                        : nil,
                    answerState: battleAnswerState(answerState)
                )
            }
        )
    }

    private func progress(_ question: CompetitiveQuestion) -> some View {
        TimelineView(.animation) { timeline in
            let remaining = state.phase == .questionOpen
                ? max(0, (question.deadlineEpochMS / 1_000) - timeline.date.timeIntervalSince1970)
                : nil
            BattleProgressHeader(
                questionNumber: question.questionIndex + 1,
                totalCount: CompetitiveClientDisplay.questionCount,
                remaining: remaining,
                timeLimit: max(1, (question.deadlineEpochMS - question.openedAtEpochMS) / 1_000)
            )
        }
    }

    private func answerArea(_ question: CompetitiveQuestion) -> some View {
        BattleChoiceList(
            choices: question.choices.map(\.text),
            myChoice: question.choices.first { $0.answerId == selectedAnswerId }?.text,
            canAnswer: canAnswer
        ) { selectedText in
            guard let choice = question.choices.first(where: { $0.text == selectedText }),
                  let service = coordinator.battleService,
                  let context = service.displayedQuestionContext(),
                  context.questionId == question.questionId,
                  context.questionIndex == question.questionIndex,
                  context.stateVersion == state.stateVersion else { return }
            selectedAnswerId = choice.answerId
            submittedContext = context
            Haptics.impact(.heavy)
            Task {
                await coordinator.submitAnswer(
                    answerId: choice.answerId,
                    displayedQuestion: context
                )
                if coordinator.userMessage != nil,
                   submittedContext == context,
                   myParticipant?.answered != true {
                    selectedAnswerId = nil
                    submittedContext = nil
                }
            }
        }
    }

    private var canAnswer: Bool {
        state.phase == .questionOpen
            && myParticipant?.active == true
            && myParticipant?.answered == false
            && myParticipant?.status == .connected
            && submittedContext == nil
            && !coordinator.isSubmittingAnswer
    }

    private func resultSummary(_ question: CompetitiveQuestion) -> some View {
        let correctText = question.choices.first {
            $0.answerId == state.questionResult?.correctAnswerId
        }?.text ?? "—"
        let correctUIDs = state.questionResult?.correctUIDs ?? []
        return BattleRevealCard(
            reveal: .init(correctAnswer: correctText, correctIDs: correctUIDs),
            correctNames: state.participants
                .filter { correctUIDs.contains($0.uid) }
                .map(\.displayName)
        )
    }

    private func battleAnswerState(
        _ state: CompetitiveClientDisplay.AnswerState
    ) -> BattleScoreBoard.DisplayAnswerState? {
        switch state {
        case .none: nil
        case .answered: .answered
        case .correct: .correct
        case .wrong: .wrong
        }
    }

    @ViewBuilder
    private var reconnectOverlay: some View {
        if let participant = myParticipant, participant.status == .reconnecting {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                    Text("再接続中")
                        .font(.headline)
                    if let deadline = participant.reconnectDeadlineEpochMS {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let remaining = max(
                                0,
                                Int(((deadline / 1_000) - timeline.date.timeIntervalSince1970).rounded(.up))
                            )
                            Text("残り\(remaining)秒")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        } else if coordinator.battleService?.listeningError != nil {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("通信を確認しています")
                        .font(.headline)
                    Button("再接続する") {
                        Task { await coordinator.retryConnection() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
