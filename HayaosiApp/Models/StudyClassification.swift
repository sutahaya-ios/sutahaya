import Foundation

/// 学習カテゴリ。ジャンルごとの出題範囲を表す。カテゴリを追加するときはここへ足す
enum StudyCategory: String, Codable, CaseIterable, Identifiable {
    case juniorHigh = "junior_high"
    case highSchool = "high_school"
    case toeic = "toeic"
    case spiVerbal = "spi_verbal"
    case spiNonVerbal = "spi_nonverbal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .juniorHigh: return "中学英単語"
        case .highSchool: return "高校英単語"
        case .toeic: return "TOEIC単語"
        case .spiVerbal: return "SPI 言語"
        case .spiNonVerbal: return "SPI 非言語"
        }
    }

    /// 属するジャンル。ジャンル側で持つと追加のたびに両方直すことになるため、カテゴリが親を指す
    var genre: Genre {
        switch self {
        case .juniorHigh, .highSchool, .toeic: return .englishWord
        case .spiVerbal, .spiNonVerbal: return .spi
        }
    }

    /// 出題数の単位。SPIは「語」ではなく「問」
    var questionUnit: String {
        switch genre {
        case .englishWord: return "語"
        case .spi: return "問"
        }
    }

    /// 選択できる出題形式。形式が未定のカテゴリでは選択UIを出さない
    var formats: [QuestionFormat] {
        self == .spiVerbal ? QuestionFormat.allCases : []
    }

    /// 既定の制限時間(秒)
    var defaultTimeLimit: TimeInterval {
        switch self {
        case .juniorHigh, .highSchool, .toeic: return QuizDefaults.timeLimit
        case .spiVerbal: return 60
        case .spiNonVerbal: return 120
        }
    }
}

/// SPI言語の出題形式。rawValueは配布JSONとルーム設定で共用する
enum QuestionFormat: String, Codable, CaseIterable, Identifiable {
    case twoWordRelation = "two_word_relation"
    case wordMeaning = "word_meaning"
    case wordUsage = "word_usage"
    case sentenceOrder = "sentence_order"
    case fillBlank = "fill_blank"
    case reading = "reading"
    case kanjiCompound = "kanji_compound"

    var id: String { rawValue }

    /// 短い語句を比較する形式では、本文を大きく中央に配置する。
    var usesProminentCenteredBody: Bool {
        switch self {
        case .twoWordRelation, .wordMeaning, .wordUsage, .kanjiCompound:
            return true
        case .sentenceOrder, .fillBlank, .reading:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .twoWordRelation: return "二語の関係"
        case .wordMeaning: return "語句の意味"
        case .wordUsage: return "語句の用法"
        case .sentenceOrder: return "文の並び替え"
        case .fillBlank: return "空欄補充"
        case .reading: return "長文読解"
        case .kanjiCompound: return "熟語の成り立ち"
        }
    }
}

/// 各カテゴリ内で共通して使う5段階の難易度
enum StudyDifficulty: Int, Codable, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var starDisplay: String {
        String(repeating: "★", count: rawValue)
            + String(repeating: "☆", count: Self.allCases.count - rawValue)
    }
}

extension Collection where Element == Question {
    /// カテゴリ・難易度・形式で絞り込む。nilの条件は「すべて」を対象にする
    func matching(
        category: StudyCategory?,
        difficulty: StudyDifficulty?,
        format: QuestionFormat? = nil
    ) -> [Question] {
        filter { question in
            let matchesCategory = category.map { question.category == $0 } ?? true
            // レベルを使わないジャンルは、保存済みの★やルーム設定の★が残っていても全問を対象にする
            let matchesDifficulty = !question.category.genre.usesDifficultyLevels
                || (difficulty.map { question.difficulty == $0 } ?? true)
            let matchesFormat = format.map { question.format == $0 } ?? true
            return matchesCategory && matchesDifficulty && matchesFormat
        }
    }
}
