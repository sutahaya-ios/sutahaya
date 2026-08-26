import Foundation

/// 配布用の英単語1件ぶん
struct WordEntry: Identifiable, Equatable {
    let id: String
    let word: String
    let meaning: String
    let pos: PartOfSpeech
    /// JSONには持たせない。どのファイルから読み込んだかで決まるため、投入時に与える
    let category: WordCategory
    let difficulty: WordDifficulty

    /// 同じカテゴリ内の重複検査に使う。大文字小文字と前後空白は区別しない
    var normalizedWordKey: String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
