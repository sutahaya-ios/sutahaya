import SwiftUI
import SwiftData
import Combine

/// 出題画面(練習・復習共通)。要件 §9-2
struct QuizSessionView: View {
    private static let tickInterval: TimeInterval = 0.1
    private static let warningThreshold: TimeInterval = 5

    let mode: PlayMode
    let timeLimit: TimeInterval
    private let sourceQuestions: [Question]

    @State private var session: QuizSession
    @State private var hasRecorded = false
    @State private var showAbortDialog = false
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
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .finished {
                recordIfNeeded()
            }
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
                .tint(session.remainingTime < Self.warningThreshold ? .red : .accentColor)

            Spacer()

            Text(entry.question.text)
                .font(.system(size: 40, weight: .bold))
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                ForEach(entry.shuffledChoices, id: \.self) { choice in
                    ChoiceButton(choice: choice, entry: entry, phase: session.phase) {
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

    private func feedbackFooter(entry: QuizSession.Entry) -> some View {
        VStack(spacing: 12) {
            if entry.didTimeout {
                Label("時間切れ", systemImage: "clock.badge.xmark")
                    .foregroundStyle(.red)
            } else if entry.isCorrect {
                Label("正解!", systemImage: "circle")
                    .foregroundStyle(.green)
            } else {
                Label("不正解", systemImage: "xmark")
                    .foregroundStyle(.red)
            }

            Button(session.isLastQuestion ? "結果を見る" : "次の問題へ") {
                session.advance()
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.headline)
    }

    private func recordIfNeeded() {
        guard !hasRecorded, !session.entries.isEmpty else { return }
        hasRecorded = true
        ResultRecorder.record(entries: session.entries, mode: mode, context: modelContext)
    }

    private func retry() {
        session = QuizSession(questions: sourceQuestions.shuffled(), timeLimit: timeLimit)
        hasRecorded = false
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
        .disabled(phase != .answering)
    }

    private var tint: Color {
        guard phase == .feedback else { return .accentColor }
        if choice == entry.question.answer { return .green }
        if choice == entry.selectedChoice { return .red }
        return .gray
    }
}
