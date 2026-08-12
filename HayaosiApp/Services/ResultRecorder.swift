import Foundation
import SwiftData

/// 解答結果の記録と復習リストの更新(要件 §5.3・§5.4)
enum ResultRecorder {
    /// 解答履歴を保存し、間違えた問題は復習リストへ登録・回数加算、
    /// 正解できた問題は復習リストから外す(克服したら卒業)
    static func record(results: [(questionID: String, isCorrect: Bool)], mode: PlayMode, context: ModelContext) {
        guard !results.isEmpty else { return }
        insertResults(results, mode: mode, context: context)
        save(context: context)
    }

    static func record(
        entries: [QuizSession.Entry],
        mode: PlayMode,
        elapsedSeconds: TimeInterval? = nil,
        context: ModelContext
    ) {
        guard !entries.isEmpty else { return }
        insertResults(
            entries.map { ($0.question.id, $0.isCorrect) },
            mode: mode,
            context: context
        )
        if let elapsedSeconds {
            addStudyTime(
                elapsedSeconds: elapsedSeconds,
                entries: entries,
                mode: mode,
                context: context
            )
        }
        save(context: context)
    }

    private static func insertResults(
        _ results: [(questionID: String, isCorrect: Bool)],
        mode: PlayMode,
        context: ModelContext
    ) {
        for result in results {
            let record = AnswerRecord(questionID: result.questionID, isCorrect: result.isCorrect, mode: mode)
            context.insert(record)
            updateReviewItem(questionID: result.questionID, isCorrect: result.isCorrect, context: context)
        }
    }

    private static func addStudyTime(
        elapsedSeconds: TimeInterval,
        entries: [QuizSession.Entry],
        mode: PlayMode,
        context: ModelContext
    ) {
        guard mode == .practice, elapsedSeconds > 0 else { return }

        let categoryCounts = Dictionary(grouping: entries, by: { $0.question.category })
            .mapValues(\.count)
        // 復習ではカテゴリが混在するため、按分せず出題数が最も多いカテゴリへ全時間を加算する。
        guard let category = WordCategory.allCases.max(by: {
            categoryCounts[$0, default: 0] < categoryCounts[$1, default: 0]
        }) else {
            return
        }

        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<StudyTimeTotal>(
            predicate: #Predicate { $0.categoryRaw == categoryRaw }
        )
        do {
            if let total = try context.fetch(descriptor).first {
                total.totalSeconds += elapsedSeconds
            } else {
                context.insert(StudyTimeTotal(category: category, totalSeconds: elapsedSeconds))
            }
        } catch {
            print("学習時間の更新に失敗: \(error)")
        }
    }

    private static func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("解答履歴の保存に失敗: \(error)")
        }
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
