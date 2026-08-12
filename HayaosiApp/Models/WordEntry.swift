import Foundation

/// 配布用の英単語JSON 1件ぶん
struct WordEntry: Codable, Identifiable, Equatable {
    let id: String
    let word: String
    let meaning: String
    let pos: PartOfSpeech
    let category: WordCategory
    let difficulty: WordDifficulty

    /// 同じカテゴリ内の重複検査に使う。大文字小文字と前後空白は区別しない
    var normalizedWordKey: String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
