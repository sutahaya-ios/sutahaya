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

    init(id: String, genre: Genre, type: QuestionType, text: String, choices: [String], answer: String) {
        self.id = id
        self.genreRaw = genre.rawValue
        self.typeRaw = type.rawValue
        self.text = text
        self.choices = choices
        self.answer = answer
    }

    var genre: Genre { Genre(rawValue: genreRaw) ?? .englishWord }
    var type: QuestionType { QuestionType(rawValue: typeRaw) ?? .multipleChoice }
}
