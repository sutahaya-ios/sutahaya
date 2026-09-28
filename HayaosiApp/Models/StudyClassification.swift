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

    /// 既定の制限時間(秒)
    var defaultTimeLimit: TimeInterval {
        switch self {
        case .juniorHigh, .highSchool, .toeic: return QuizDefaults.timeLimit
        case .spiVerbal: return 60
        case .spiNonVerbal: return 120
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
    /// 指定されたカテゴリと難易度で絞り込む。nilはオンライン対戦用の「指定なし」
    func matching(category: StudyCategory?, difficulty: StudyDifficulty?) -> [Question] {
        filter { question in
            let matchesCategory = category.map { question.category == $0 } ?? true
            let matchesDifficulty = difficulty.map { question.difficulty == $0 } ?? true
            return matchesCategory && matchesDifficulty
        }
    }
}
