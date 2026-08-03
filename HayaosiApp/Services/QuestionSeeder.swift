import Foundation
import SwiftData

/// バンドルの問題データ(JSON)をSwiftDataへ投入する
enum QuestionSeeder {
    /// 問題データを更新したらこの値を上げる(次回起動時に再投入される)
    static let dataVersion = 2
    private static let versionKey = "questionDataVersion"
    private static let distractorCount = 3
    /// 誤答選択の巡回ストライド。品詞グループ数と互いに素な素数にする
    private static let distractorStride = 11

    private struct WordEntry: Decodable {
        let word: String
        let pos: String
        let meaning: String
        /// 文字送り型で出す説明文(任意)。無ければ meaning を使う。
        /// 長い文ほど「どこまで読んで押すか」の駆け引きが効くので、データ拡充時はここを充実させる
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

    /// 1単語につき出題形式ごとの問題を作る(速答型=単語→意味 / 文字送り型=意味→単語)。
    /// 誤答は同じ品詞の他単語から決定的に選ぶ
    private static func makeQuestions(from entries: [WordEntry]) -> [Question] {
        let groups = Dictionary(grouping: entries, by: \.pos)
        var questions: [Question] = []
        for (index, entry) in entries.enumerated() {
            guard let group = groups[entry.pos] else { continue }
            let number = index + 1

            questions.append(Question(
                id: String(format: "en_%04d", number),
                genre: .englishWord,
                type: .multipleChoice,
                style: .speed,
                text: entry.word,
                choices: [entry.meaning] + distractors(for: entry, in: group, using: \.meaning),
                answer: entry.meaning
            ))

            questions.append(Question(
                id: String(format: "pw_%04d", number),
                genre: .englishWord,
                type: .multipleChoice,
                style: .progressive,
                text: entry.definition ?? entry.meaning,
                choices: [entry.word] + distractors(for: entry, in: group, using: \.word),
                answer: entry.word
            ))
        }
        return questions
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
