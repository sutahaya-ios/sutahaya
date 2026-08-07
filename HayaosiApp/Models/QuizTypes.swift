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

/// 対戦の出題形式(要件 §5.1.2)。問題データは共通で、見せ方と回答のしかたが違う
enum QuizStyle: String, Codable, CaseIterable, Identifiable {
    /// 文字送り型:単語が1文字ずつ表示される。4択は最初から全員に見えていて、
    /// **選択肢を押した瞬間が「早押し+回答」**。早く答えるほど手がかりが少ない
    case progressiveChoice = "progressive_choice"
    /// 速答型:単語を全部見せてから早押しボタン。押した人だけが4択に答える(従来方式)
    case speed = "speed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .progressiveChoice: return "文字送り型"
        case .speed: return "速答型"
        }
    }

    /// 設定画面のフッターで出す説明
    var detail: String {
        switch self {
        case .progressiveChoice:
            return "単語が1文字ずつ表示されます。4択は最初から全員に見えていて、選択肢を押した瞬間が回答です。早く答えるほど手がかりが少なくなります。"
        case .speed:
            return "単語を全部表示してから早押しボタンを押します。押した人だけが4択に答えられます。"
        }
    }

    /// 問題文を少しずつ見せるか
    var revealsProgressively: Bool { self == .progressiveChoice }

    /// 早押しボタンを使うか(false なら選択肢のタップがそのまま回答になる)
    var usesBuzzButton: Bool { self == .speed }
}

/// 出題設定のデフォルト値・選択肢(練習・対戦で共通。要件 §5.1.3)
enum QuizDefaults {
    static let questionCount = 10
    static let timeLimit: TimeInterval = 20
    /// 単語バトルの標準は文字送り型(駆け引きが生まれるため)。設定で速答型にも変えられる
    static let style = QuizStyle.progressiveChoice
    static let questionCountOptions = [5, 10, 15, 20]
    static let timeLimitOptions: [TimeInterval] = [10, 20, 30]
}
