import Foundation
import SwiftData

/// ローカル問題データ(要件 §8.1)
@Model
final class Question {
    @Attribute(.unique) var id: String
    var genreRaw: String
    var typeRaw: String
    /// 出題形式(速答型/文字送り型)。同じ単語から形式ごとに別の問題を作る
    var styleRaw: String = QuizStyle.speed.rawValue
    /// 問題文(速答型では単語、文字送り型では意味・説明文)
    var text: String
    /// 正答を含む選択肢。表示時にシャッフルする
    var choices: [String]
    var answer: String

    init(id: String, genre: Genre, type: QuestionType, style: QuizStyle,
         text: String, choices: [String], answer: String) {
        self.id = id
        self.genreRaw = genre.rawValue
        self.typeRaw = type.rawValue
        self.styleRaw = style.rawValue
        self.text = text
        self.choices = choices
        self.answer = answer
    }

    var genre: Genre { Genre(rawValue: genreRaw) ?? .englishWord }
    var type: QuestionType { QuestionType(rawValue: typeRaw) ?? .multipleChoice }
    var style: QuizStyle { QuizStyle(rawValue: styleRaw) ?? .speed }
}
