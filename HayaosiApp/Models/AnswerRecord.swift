import Foundation
import SwiftData

/// 解答履歴(要件 §8.1)。対戦・練習の正誤を蓄積し学習履歴として使う
@Model
final class AnswerRecord {
    var questionID: String
    var isCorrect: Bool
    var answeredAt: Date
    var modeRaw: String

    init(questionID: String, isCorrect: Bool, mode: PlayMode, answeredAt: Date = .now) {
        self.questionID = questionID
        self.isCorrect = isCorrect
        self.modeRaw = mode.rawValue
        self.answeredAt = answeredAt
    }

    var mode: PlayMode { PlayMode(rawValue: modeRaw) ?? .practice }
}
