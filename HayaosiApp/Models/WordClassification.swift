import Foundation

/// 英単語の学習カテゴリ。試験別カテゴリを追加するときはここへ足す
enum WordCategory: String, Codable, CaseIterable, Identifiable {
    case juniorHigh = "junior_high"
    case highSchool = "high_school"
    case toeic = "toeic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .juniorHigh: return "中学英単語"
        case .highSchool: return "高校英単語"
        case .toeic: return "TOEIC単語"
        }
    }
}

/// 各カテゴリ内で共通して使う5段階の難易度
enum WordDifficulty: Int, Codable, CaseIterable, Identifiable {
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
    func matching(category: WordCategory?, difficulty: WordDifficulty?) -> [Question] {
        filter { question in
            let matchesCategory = category.map { question.category == $0 } ?? true
            let matchesDifficulty = difficulty.map { question.difficulty == $0 } ?? true
            return matchesCategory && matchesDifficulty
        }
    }
}
