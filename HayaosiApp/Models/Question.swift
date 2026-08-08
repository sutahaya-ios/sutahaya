import Foundation
import SwiftData

/// ローカル問題データ(要件 §8.1)
@Model
final class Question {
    @Attribute(.unique) var id: String
    var genreRaw: String
    var typeRaw: String
    /// 問題文(英単語ジャンルでは単語そのもの)
    var text: String
    /// 正答を含む選択肢。表示時にシャッフルする
    var choices: [String]
    var answer: String
    /// 英単語の学習カテゴリ。既存インストールを壊さないためデフォルト値付き
    var categoryRaw: String = WordCategory.highSchool.rawValue
    /// カテゴリ内の難易度(1〜5)。既存インストールを壊さないためデフォルト値付き
    var difficultyValue: Int = WordDifficulty.one.rawValue

    init(id: String, genre: Genre, type: QuestionType,
         text: String, choices: [String], answer: String,
         category: WordCategory = .highSchool,
         difficulty: WordDifficulty = .one) {
        self.id = id
        self.genreRaw = genre.rawValue
        self.typeRaw = type.rawValue
        self.text = text
        self.choices = choices
        self.answer = answer
        self.categoryRaw = category.rawValue
        self.difficultyValue = difficulty.rawValue
    }

    var genre: Genre { Genre(rawValue: genreRaw) ?? .englishWord }
    var type: QuestionType { QuestionType(rawValue: typeRaw) ?? .multipleChoice }
    var category: WordCategory { WordCategory(rawValue: categoryRaw) ?? .highSchool }
    var difficulty: WordDifficulty { WordDifficulty(rawValue: difficultyValue) ?? .one }
}
