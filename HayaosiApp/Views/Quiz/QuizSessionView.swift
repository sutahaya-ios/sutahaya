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

    let mode: PlayMode
    let timeLimit: TimeInterval
    private let sourceQuestions: [Question]

    @State private var session: QuizSession
    @State private var hasRecorded = false
    @State private var showAbortDialog = false
    @State private var sessionStartedAt: Date?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: Self.tickInterval, on: .main, in: .common).autoconnect()

    init(questions: [Question], timeLimit: TimeInterval, mode: PlayMode) {
        self.sourceQuestions = questions
        self.timeLimit = timeLimit
        self.mode = mode
        _session = State(initialValue: QuizSession(questions: questions, timeLimit: timeLimit))
    }

    var body: some View {
        Group {
            if session.phase == .finished {
                QuizResultView(session: session, onRetry: retry, onClose: { dismiss() })
            } else if let entry = session.currentEntry {
                questionBody(entry: entry)
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
        .onReceive(timer) { _ in
            session.tick(Self.tickInterval)
        }
        .task(id: session.phase) {
            await advanceAfterFeedback()
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

            Spacer()

            QuestionTextView(
                text: entry.question.text,
                mode: .full,
                isSingleWord: entry.question.genre.usesProgressiveReveal
            )

            if let table = entry.question.table {
                QuestionTableView(table: table)
            }

            Spacer()

            VStack(spacing: 12) {
                ForEach(entry.shuffledChoices, id: \.self) { choice in
                    ChoiceButton(choice: choice, entry: entry, phase: session.phase) {
                        Haptics.impact(.light)
                        session.select(choice)
                    }
                }
            }

            if session.phase == .feedback {
                feedbackFooter(entry: entry)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func feedbackFooter(entry: QuizSession.Entry) -> some View {
        VStack(spacing: 14) {
            if entry.didTimeout {
                Label("時間切れ", systemImage: "clock.badge.xmark")
                    .foregroundStyle(.red)
                    .font(.headline)
            } else if entry.isCorrect {
                Label("正解!", systemImage: "circle")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Label("不正解", systemImage: "xmark")
                    .foregroundStyle(.red)
                    .font(.headline)
            }

            if !entry.question.explanation.isEmpty {
                QuestionExplanationView(explanation: entry.question.explanation)

                Button("次へ") {
                    session.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
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
