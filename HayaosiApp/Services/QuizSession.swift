import Foundation
import Observation

/// 一人練習・対戦で共通利用する出題エンジン(要件 §5.2・§5.3)
/// タイマーはView側から tick() で駆動する(自前でTimerを持たない方がテストしやすいため)
@Observable
final class QuizSession {
    enum Phase: Equatable {
        case answering // 回答受付中
        case feedback  // 正誤表示中
        case finished  // 全問終了
    }

    struct Entry {
        let question: Question
        let shuffledChoices: [String]
        var selectedChoice: String?
        var didTimeout = false

        var isCorrect: Bool { selectedChoice == question.answer }
    }

    let timeLimit: TimeInterval
    private(set) var entries: [Entry]
    private(set) var currentIndex = 0
    private(set) var phase: Phase = .answering
    private(set) var remainingTime: TimeInterval

    init(questions: [Question], timeLimit: TimeInterval) {
        self.timeLimit = timeLimit
        self.remainingTime = timeLimit
        self.entries = questions.map {
            Entry(question: $0, shuffledChoices: $0.choices.shuffled())
        }
        if entries.isEmpty {
            phase = .finished
        }
    }

    var currentEntry: Entry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }

    var totalCount: Int { entries.count }
    var correctCount: Int { entries.filter(\.isCorrect).count }
    var wrongCount: Int { totalCount - correctCount }
    func select(_ choice: String) {
        guard phase == .answering else { return }
        entries[currentIndex].selectedChoice = choice
        phase = .feedback
    }

    /// View側のタイマーから呼ぶ。時間切れは不正解扱い(要件 §5.1.2 準拠の練習版)
    func tick(_ delta: TimeInterval) {
        guard phase == .answering else { return }
        remainingTime = max(0, remainingTime - delta)
        if remainingTime <= 0 {
            entries[currentIndex].didTimeout = true
            phase = .feedback
        }
    }

    func advance() {
        guard phase == .feedback else { return }
        if currentIndex + 1 < entries.count {
            currentIndex += 1
            remainingTime = timeLimit
            phase = .answering
        } else {
            phase = .finished
        }
    }
}
