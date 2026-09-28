import Foundation

/// 問題の回答形式。将来「並べ替え」等を追加しても既存データに影響しない構造にする(要件 §5.2)
enum QuestionType: String, Codable, CaseIterable {
    case multipleChoice = "multiple_choice" // 4択
    case textInput = "text_input"           // 入力式(v1.0で導入予定)
}

/// 出題ジャンル。カテゴリ(出題範囲)の親にあたる
enum Genre: String, Codable, CaseIterable, Identifiable {
    case englishWord = "english_word"
    case spi = "spi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishWord: return "英単語"
        case .spi: return "SPI"
        }
    }

    /// 問題文を1文字ずつ出すか。SPIは読解と計算が要るため最初から全文を見せる
    var usesProgressiveReveal: Bool {
        switch self {
        case .englishWord: return true
        case .spi: return false
        }
    }

    /// 選択肢の並びをシャッフルするか。SPIは作問時の並び(数値なら昇順)を保つ
    var shufflesChoices: Bool {
        switch self {
        case .englishWord: return true
        case .spi: return false
        }
    }

    var categories: [StudyCategory] {
        StudyCategory.allCases.filter { $0.genre == self }
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

    /// 制限時間の選択肢はカテゴリごとに違う。SPIは読解と計算の時間が要る
    static func timeLimitOptions(for category: StudyCategory) -> [TimeInterval] {
        switch category.genre {
        case .englishWord: return [5, 10, 20, 30]
        case .spi: return [30, 60, 120, 180]
        }
    }
}
