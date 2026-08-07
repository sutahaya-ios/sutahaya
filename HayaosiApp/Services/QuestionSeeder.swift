import Foundation
import SwiftData

/// バンドルの問題データ(JSON)をSwiftDataへ投入する
enum QuestionSeeder {
    /// 問題データを更新したらこの値を上げる(次回起動時に再投入される)
    static let dataVersion = 4
    private static let versionKey = "questionDataVersion"
    private static let distractorCount = 3
    /// 誤答選択の巡回ストライド。品詞グループ数と互いに素な素数にする
    private static let distractorStride = 11

    private struct WordEntry: Decodable {
        let word: String
        let pos: String
        let meaning: String
        /// 語の説明文(任意)。現在の出題では未使用だが、ジャンル追加や入力式(v1.5)で使えるよう残している
        let definition: String?
    }

    static func seedIfNeeded(context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < dataVersion else { return }
        do {
            let entries = try loadEntries()
            // 旧データを入れ替える。履歴・復習リストはquestionIDで別管理なので影響しない
            try context.delete(model: Question.self)
            for question in makeQuestions(from: entries) {
                context.insert(question)
            }
            try context.save()
            UserDefaults.standard.set(dataVersion, forKey: versionKey)
        } catch {
            print("問題データの投入に失敗: \(error)")
        }
    }

    private static func loadEntries() throws -> [WordEntry] {
        guard let url = Bundle.main.url(forResource: "english_words", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([WordEntry].self, from: Data(contentsOf: url))
    }

    /// 「単語 → 意味を4択」の問題を作る。出題形式(速答型/文字送り型)は見せ方の違いなので、
    /// 問題データは共通で1セットだけ持つ。誤答は同じ品詞の他単語から決定的に選ぶ
    private static func makeQuestions(from entries: [WordEntry]) -> [Question] {
        let groups = Dictionary(grouping: entries, by: \.pos)
        return entries.enumerated().compactMap { index, entry in
            guard let group = groups[entry.pos] else { return nil }
            return Question(
                id: String(format: "en_%04d", index + 1),
                genre: .englishWord,
                type: .multipleChoice,
                text: entry.word,
                choices: [entry.meaning] + distractors(for: entry, in: group, using: \.meaning),
                answer: entry.meaning
            )
        }
    }

    private static func distractors(
        for entry: WordEntry,
        in group: [WordEntry],
        using key: KeyPath<WordEntry, String>
    ) -> [String] {
        guard let base = group.firstIndex(where: { $0.word == entry.word }) else { return [] }
        let correct = entry[keyPath: key]
        var result: [String] = []
        for step in 1..<group.count where result.count < distractorCount {
            let candidate = group[(base + step * distractorStride) % group.count][keyPath: key]
            if candidate != correct && !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }
}
