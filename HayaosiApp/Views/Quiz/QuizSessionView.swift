import SwiftUI
import SwiftData
import Combine

/// 出題画面(練習・復習共通)。要件 §9-2
struct QuizSessionView: View {
    /// 残り時間の更新間隔。バーの段差が見えないよう毎フレーム進める
    private static let tickInterval: TimeInterval = 1.0 / 60.0
    /// 正誤表示を見せてから次の問題へ進むまでの時間。
    /// 不正解のほうが長いのは、正答を読む時間が要るため
    private static let correctFeedbackDuration: TimeInterval = 0.7
    private static let wrongFeedbackDuration: TimeInterval = 1.6
    private static let answerFeedbackDuration: TimeInterval = 1.2
    private static let nextButtonVerticalPadding: CGFloat = 12

    let mode: PlayMode
    private let showsInterstitial: Bool
    let timeLimit: TimeInterval
    private let sourceQuestions: [Question]

    @State private var session: QuizSession
    @State private var hasRecorded = false
    @State private var showAbortDialog = false
    @State private var showsAnswerFeedback = false
    @State private var showsExplanation = false
    @State private var advancesAfterExplanation = false
    @State private var sessionStartedAt: Date?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: Self.tickInterval, on: .main, in: .common).autoconnect()

    /// 復習から始めた場合は広告を出さない。学習行動を止めないため(要件 §4.2)
    init(
        questions: [Question],
        timeLimit: TimeInterval,
        mode: PlayMode,
        showsInterstitial: Bool = true
    ) {
        self.sourceQuestions = questions
        self.timeLimit = timeLimit
        self.mode = mode
        self.showsInterstitial = showsInterstitial
        _session = State(initialValue: QuizSession(questions: questions, timeLimit: timeLimit))
    }

    var body: some View {
        Group {
            if session.phase == .finished {
                QuizResultView(
                    session: session,
                    onRetry: { leaveResultAfterInterstitial(then: retry) },
                    onClose: { leaveResultAfterInterstitial(then: { dismiss() }) }
                )
            } else if let entry = session.currentEntry {
                questionBody(entry: entry)
            }
        }
        .overlay {
            if session.phase == .feedback, showsAnswerFeedback,
               let entry = session.currentEntry {
                AnswerFeedbackSymbol(isCorrect: entry.isCorrect)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(session.phase != .finished)
        .toolbar {
            if session.phase != .finished {
                ToolbarItem(placement: .topBarLeading) {
                    Button("中断") {
                        showAbortDialog = true
                    }
                }
            }
        }
        .confirmationDialog("練習を中断しますか?", isPresented: $showAbortDialog, titleVisibility: .visible) {
            Button("中断する", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("ここまでの解答は記録されません")
        }
        .sheet(isPresented: $showsExplanation, onDismiss: finishExplanation) {
            if let entry = session.currentEntry {
                QuizExplanationSheet(
                    question: entry.question,
                    questionNumber: session.currentIndex + 1,
                    userAnswer: entry.selectedChoice.map { .selected($0) } ?? .timedOut
                ) {
                    advancesAfterExplanation = true
                    showsExplanation = false
                }
                .presentationDetents([.large])
            }
        }
        .onReceive(timer) { _ in
            session.tick(Self.tickInterval)
        }
        .task(id: session.phase) {
            await advanceAfterFeedback()
        }
        .task(id: session.phase) {
            await animateAnswerFeedback()
        }
        .onAppear {
            if sessionStartedAt == nil {
                sessionStartedAt = .now
            }
        }
        .onChange(of: session.phase) { _, newPhase in
            switch newPhase {
            case .answering:
                break
            case .feedback:
                playFeedbackSound()
            case .finished:
                SoundPlayer.shared.play(.fanfare)
                recordIfNeeded()
                if showsInterstitial {
                    AdsService.shared.recordSessionFinished(.quiz)
                }
            }
        }
    }

    private func playFeedbackSound() {
        guard let entry = session.currentEntry else { return }
        if entry.didTimeout {
            SoundPlayer.shared.play(.timeUp)
        } else if entry.isCorrect {
            SoundPlayer.shared.play(.correct)
        } else {
            SoundPlayer.shared.play(.wrong)
        }
    }

    private func questionBody(entry: QuizSession.Entry) -> some View {
        ScrollView {
            questionContent(entry: entry)
                .padding()
        }
        // 長い問題を読んだあとも、次問は問題番号から表示する。
        .id(session.currentIndex)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.phase == .feedback && !entry.question.explanation.isEmpty {
                feedbackButtons
            }
        }
    }

    private func questionContent(entry: QuizSession.Entry) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("第\(session.currentIndex + 1)問 / \(session.totalCount)問")
                Spacer()
                Text("残り\(Int(session.remainingTime.rounded(.up)))秒")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ProgressView(value: session.remainingTime, total: timeLimit)
                .tint(
                    session.remainingTime < TimerBarStyle.urgentThreshold(for: timeLimit)
                        ? TimerBarStyle.urgentTint
                        : TimerBarStyle.normalTint
                )

            QuestionTextView(
                text: entry.question.text,
                mode: .full,
                isSingleWord: entry.question.genre.usesProgressiveReveal,
                format: entry.question.format
            )
            .fixedSize(horizontal: false, vertical: true)

            if let table = entry.question.table {
                QuestionTableView(table: table)
            }

            VStack(spacing: 12) {
                ForEach(entry.shuffledChoices, id: \.self) { choice in
                    ChoiceButton(choice: choice, entry: entry, phase: session.phase) {
                        Haptics.impact(.light)
                        session.select(choice)
                    }
                }
            }
        }
    }

    /// ○×の表示後、タブバーの上から解説と次問を選べるようにする。
    private var feedbackButtons: some View {
        HStack(spacing: 12) {
            Button {
                showsExplanation = true
            } label: {
                Label("解説", systemImage: "text.book.closed")
            }
            .buttonStyle(.bordered)

            Button {
                session.advance()
            } label: {
                Text("次へ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(showsAnswerFeedback)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, Self.nextButtonVerticalPadding)
        .background(.bar)
    }

    /// シートが閉じきってから進め、次問の制限時間を開始する。
    private func finishExplanation() {
        guard advancesAfterExplanation else { return }
        advancesAfterExplanation = false
        session.advance()
    }

    /// 自動進行とは独立して消す。次問への遷移・画面退出時はtaskがキャンセルされる。
    private func animateAnswerFeedback() async {
        showsAnswerFeedback = false
        guard session.phase == .feedback else { return }
        withAnimation(BattleAnimation.reveal) {
            showsAnswerFeedback = true
        }
        do {
            try await Task.sleep(for: .seconds(Self.answerFeedbackDuration))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        withAnimation(BattleAnimation.reveal) {
            showsAnswerFeedback = false
        }
    }

    /// 正誤表示中だけ待って次の問題へ進む。
    /// 解説がある問題は読む時間が人によって違うので、自動で進めず「次へ」に任せる。
    /// 画面を離れたときと次のフェーズへ移ったときは .task(id:) がキャンセルする
    private func advanceAfterFeedback() async {
        guard session.phase == .feedback else { return }
        guard session.currentEntry?.question.explanation.isEmpty ?? true else { return }
        let duration = session.currentEntry?.isCorrect == true
            ? Self.correctFeedbackDuration
            : Self.wrongFeedbackDuration
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            return
        }
        session.advance()
    }

    private func recordIfNeeded() {
        guard !hasRecorded, !session.entries.isEmpty else { return }
        hasRecorded = true
        let elapsedSeconds = sessionStartedAt.map { Date.now.timeIntervalSince($0) }
        ResultRecorder.record(
            entries: session.entries,
            mode: mode,
            elapsedSeconds: elapsedSeconds,
            context: modelContext
        )
    }

    /// リザルトから離れる操作に全画面広告を挟む(要件 §4.2)。
    /// 広告が閉じてから次の動作へ進み、遷移と重ならないようにする
    private func leaveResultAfterInterstitial(then next: @escaping () -> Void) {
        guard showsInterstitial else {
            next()
            return
        }
        AdsService.shared.presentInterstitialIfDue(for: .quiz, onFinish: next)
    }

    private func retry() {
        session = QuizSession(questions: sourceQuestions.shuffled(), timeLimit: timeLimit)
        hasRecorded = false
        sessionStartedAt = .now
    }
}

/// 選択肢ボタン。正誤表示中は正答を緑・誤答選択を赤で示す
private struct ChoiceButton: View {
    let choice: String
    let entry: QuizSession.Entry
    let phase: QuizSession.Phase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(choice)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .allowsHitTesting(phase == .answering)
    }

    private var tint: Color {
        guard phase == .feedback else { return .accentColor }
        if choice == entry.question.answer { return .green }
        if choice == entry.selectedChoice { return .red }
        return .gray
    }
}
