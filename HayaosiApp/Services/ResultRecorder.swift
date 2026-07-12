import Foundation
import SwiftData

/// 解答結果の記録と復習リストの更新(要件 §5.3・§5.4)
enum ResultRecorder {
    /// 解答履歴を保存し、間違えた問題は復習リストへ登録・回数加算、
    /// 正解できた問題は復習リストから外す(克服したら卒業)
    static func record(results: [(questionID: String, isCorrect: Bool)], mode: PlayMode, context: ModelContext) {
        guard !results.isEmpty else { return }
        for result in results {
            let record = AnswerRecord(questionID: result.questionID, isCorrect: result.isCorrect, mode: mode)
            context.insert(record)
            updateReviewItem(questionID: result.questionID, isCorrect: result.isCorrect, context: context)
        }
        do {
            try context.save()
        } catch {
            print("解答履歴の保存に失敗: \(error)")
        }
    }

    static func record(entries: [QuizSession.Entry], mode: PlayMode, context: ModelContext) {
        record(
            results: entries.map { ($0.question.id, $0.isCorrect) },
            mode: mode,
            context: context
        )
    }

    private static func updateReviewItem(questionID: String, isCorrect: Bool, context: ModelContext) {
        let descriptor = FetchDescriptor<ReviewItem>(
            predicate: #Predicate { $0.questionID == questionID }
        )
        do {
            let existing = try context.fetch(descriptor).first
            if isCorrect {
                if let existing {
                    context.delete(existing)
                }
            } else if let existing {
                existing.wrongCount += 1
                existing.lastAskedAt = .now
            } else {
                context.insert(ReviewItem(questionID: questionID))
            }
        } catch {
            print("復習リストの更新に失敗: \(error)")
        }
    }
}
