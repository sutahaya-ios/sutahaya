import Foundation

/// 問題の回答形式。将来「並べ替え」等を追加しても既存データに影響しない構造にする(要件 §5.2)
enum QuestionType: String, Codable, CaseIterable {
    case multipleChoice = "multiple_choice" // 4択
    case textInput = "text_input"           // 入力式(v1.0で導入予定)
}

/// 出題ジャンル。資格・SPI風はv1.5以降に追加予定(要件 §5.5)
enum Genre: String, Codable, CaseIterable, Identifiable {
    case englishWord = "english_word"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishWord: return "英単語"
        }
    }
}

/// 解答時のプレイモード(要件 §8.1 AnswerRecord)
enum PlayMode: String, Codable {
    case practice
    case battle
}

/// 出題設定のデフォルト値・選択肢(練習・対戦で共通。要件 §5.1.3)
enum QuizDefaults {
    static let questionCount = 10
    static let timeLimit: TimeInterval = 5
    static let questionCountOptions = [5, 10, 15, 20]
    static let timeLimitOptions: [TimeInterval] = [5, 10, 20, 30]
}
