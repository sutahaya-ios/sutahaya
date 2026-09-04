import Foundation
import SwiftData

enum QuestionDataError: LocalizedError {
    case missingResource(name: String)
    case duplicateID(String)
    case duplicateWord(word: String, category: WordCategory)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "単語データ \(name).json が見つかりません"
        case .duplicateID(let id):
            return "問題ID \(id) が重複しています"
        case .duplicateWord(let word, let category):
            return "\(category.displayName)で「\(word)」が重複しています"
        }
    }
}

/// バンドルの問題データ(JSON)をSwiftDataへ投入する
enum QuestionSeeder {
    /// 問題データを更新したらこの値を上げる(次回起動時に再投入される)
    static let dataVersion = 11
    private static let versionKey = "questionDataVersion"
    private static let distractorCount = 3
    /// 誤答選択の巡回ストライド。品詞グループ数と互いに素な素数にする
    private static let distractorStride = 11

    static func seedIfNeeded(context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < dataVersion else { return }
        do {
            let entries = try loadEntries()
            try migrateQuestionReferences(to: entries, context: context)
            // QuestionはJSONから再生成できる配布データなので、全件を新構造で入れ替える
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

    /// ID体系の変更時も、同じ単語なら既存の解答履歴と復習項目を新IDへ引き継ぐ
    private static func migrateQuestionReferences(
        to entries: [WordEntry],
        context: ModelContext
    ) throws {
        let currentQuestions = try context.fetch(FetchDescriptor<Question>())
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let entriesByWord = Dictionary(grouping: entries, by: \.normalizedWordKey)
        var replacementIDByCurrentID: [String: String] = [:]

        for question in currentQuestions {
            if entriesByID[question.id] != nil {
                replacementIDByCurrentID[question.id] = question.id
                continue
            }

            let wordKey = question.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let matches = entriesByWord[wordKey] ?? []
            let categoryMatches = matches.filter { $0.category == question.category }
            if categoryMatches.count == 1 {
                replacementIDByCurrentID[question.id] = categoryMatches[0].id
            } else if matches.count == 1 {
                replacementIDByCurrentID[question.id] = matches[0].id
            }
        }

        for record in try context.fetch(FetchDescriptor<AnswerRecord>()) {
            record.questionID = replacementIDByCurrentID[record.questionID] ?? record.questionID
        }
        for item in try context.fetch(FetchDescriptor<ReviewItem>()) {
            item.questionID = replacementIDByCurrentID[item.questionID] ?? item.questionID
        }
    }

    /// JSONの1件ぶん。カテゴリはファイル名で決まるので持たせない
    private struct WordEntryFile: Decodable {
        let id: String
        let word: String
        let meaning: String
        let pos: PartOfSpeech
        let difficulty: WordDifficulty
    }

    /// 全カテゴリのファイルを読み、カテゴリ内の重複とIDの一意性を検証する
    static func loadEntries() throws -> [WordEntry] {
        var allEntries: [WordEntry] = []
        var allIDs: Set<String> = []

        for category in WordCategory.allCases {
            guard let url = Bundle.main.url(forResource: category.rawValue, withExtension: "json") else {
                throw QuestionDataError.missingResource(name: category.rawValue)
            }
            let decoded = try JSONDecoder().decode([WordEntryFile].self, from: Data(contentsOf: url))
            var wordsInCategory: Set<String> = []

            for file in decoded {
                guard allIDs.insert(file.id).inserted else {
                    throw QuestionDataError.duplicateID(file.id)
                }
                let entry = WordEntry(
                    id: file.id,
                    word: file.word,
                    meaning: file.meaning,
                    pos: file.pos,
                    category: category,
                    difficulty: file.difficulty
                )
                guard wordsInCategory.insert(entry.normalizedWordKey).inserted else {
                    throw QuestionDataError.duplicateWord(word: entry.word, category: category)
                }
                allEntries.append(entry)
            }
        }
        return allEntries
    }

    /// 「単語 → 意味を4択」の問題を作る。誤答は同じ品詞グループから決定的に選ぶ
    static func makeQuestions(from entries: [WordEntry]) -> [Question] {
        let groups = Dictionary(grouping: entries) { $0.pos.distractorGroup }
        return entries.compactMap { entry in
            guard let group = groups[entry.pos.distractorGroup] else { return nil }
            return Question(
                id: entry.id,
                genre: .englishWord,
                type: .multipleChoice,
                text: entry.word,
                choices: [entry.meaning] + distractors(for: entry, in: group, using: \.meaning),
                answer: entry.meaning,
                category: entry.category,
                difficulty: entry.difficulty
            )
        }
    }

    private static func distractors(
        for entry: WordEntry,
        in group: [WordEntry],
        using key: KeyPath<WordEntry, String>
    ) -> [String] {
        guard let base = group.firstIndex(where: { $0.id == entry.id }) else { return [] }
        let correct = entry[keyPath: key]
        let correctElements = meaningElements(from: correct)
        var result: [String] = []
        for step in 1..<group.count where result.count < distractorCount {
            let candidate = group[(base + step * distractorStride) % group.count][keyPath: key]
            let candidateElements = meaningElements(from: candidate)
            if candidate != correct
                && correctElements.isDisjoint(with: candidateElements)
                && !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }

    /// カッコ外の区切り文字で意味を分け、空白を除いた要素の集合を返す
    private static func meaningElements(from meaning: String) -> Set<String> {
        var elements: Set<String> = []
        var currentElement = ""
        var parenthesisDepth = 0

        for character in meaning {
            switch character {
            case "（", "(":
                parenthesisDepth += 1
                currentElement.append(character)
            case "）", ")":
                if parenthesisDepth > 0 {
                    parenthesisDepth -= 1
                }
                currentElement.append(character)
            case "、", "・":
                if parenthesisDepth > 0 {
                    currentElement.append(character)
                    continue
                }
                if !currentElement.isEmpty {
                    elements.insert(currentElement)
                }
                currentElement.removeAll(keepingCapacity: true)
            case " ", "　":
                continue
            default:
                currentElement.append(character)
            }
        }

        if !currentElement.isEmpty {
            elements.insert(currentElement)
        }
        return elements
    }
}
