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

/// 出題形式(要件 §5.1.2)。早押しの駆け引きの作り方が違う2種類。
/// どちらが受けるかはリリース後の反応を見て決めるため、切り替えられる設計にしている
enum QuizStyle: String, Codable, CaseIterable, Identifiable {
    /// 速答型:単語を見て意味を4択で選ぶ。問題文は最初から全部見えるので速さと知識の勝負
    case speed = "speed"
    /// 文字送り型:意味を少しずつ表示し、単語を4択で選ぶ。早く押すほど手がかりが少ない
    case progressive = "progressive"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: return "速答型"
        case .progressive: return "文字送り型"
        }
    }

    /// 設定画面のフッターで出す説明
    var detail: String {
        switch self {
        case .speed:
            return "単語 → 意味を4択。問題文は最初から全部見えるので、知っているかどうかと速さの勝負になります。"
        case .progressive:
            return "意味 → 単語を4択。問題文が少しずつ表示されるので、早く押すほど手がかりが少なくなります。"
        }
    }

    /// 問題文を少しずつ見せるか
    var revealsProgressively: Bool { self == .progressive }
}

/// 出題設定のデフォルト値・選択肢(練習・対戦で共通。要件 §5.1.3)
enum QuizDefaults {
    static let questionCount = 10
    static let timeLimit: TimeInterval = 20
    /// 単語バトルの標準は文字送り型(駆け引きが生まれるため)。設定で速答型にも変えられる
    static let style = QuizStyle.progressive
    static let questionCountOptions = [5, 10, 15, 20]
    static let timeLimitOptions: [TimeInterval] = [10, 20, 30]
}
