import XCTest
import SwiftData
@testable import HayaosiApp

/// カテゴリ・難易度の絞り込みと、収録データの整合性を検証する
final class WordClassificationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([Question.self, AnswerRecord.self, ReviewItem.self])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    private func makeQuestion(
        id: String,
        word: String,
        category: WordCategory,
        difficulty: WordDifficulty
    ) -> Question {
        let question = Question(
            id: id,
            genre: .englishWord,
            type: .multipleChoice,
            text: word,
            choices: ["a", "b", "c", "d"],
            answer: "a",
            category: category,
            difficulty: difficulty
        )
        ModelContext(container).insert(question)
        return question
    }

    private func makeEntry(
        id: String,
        word: String,
        meaning: String,
        pos: PartOfSpeech
    ) -> WordEntry {
        WordEntry(
            id: id,
            word: word,
            meaning: meaning,
            pos: pos,
            category: .toeic,
            difficulty: .one
        )
    }

    func test_カテゴリと難易度の完全一致で絞り込む() {
        let questions = [
            makeQuestion(id: "jh_0001", word: "book", category: .juniorHigh, difficulty: .one),
            makeQuestion(id: "jh_0002", word: "school", category: .juniorHigh, difficulty: .two),
            makeQuestion(id: "hs_0001", word: "book", category: .highSchool, difficulty: .one)
        ]

        let result = questions.matching(category: .juniorHigh, difficulty: .one)

        XCTAssertEqual(result.map(\.id), ["jh_0001"])
    }

    func test_カテゴリが違えば同じ単語を別問題として扱える() {
        let questions = [
            makeQuestion(id: "jh_0001", word: "book", category: .juniorHigh, difficulty: .one),
            makeQuestion(id: "hs_0001", word: "book", category: .highSchool, difficulty: .one)
        ]

        XCTAssertEqual(questions.matching(category: .juniorHigh, difficulty: .one).count, 1)
        XCTAssertEqual(questions.matching(category: .highSchool, difficulty: .one).count, 1)
    }

    func test_nil指定ならオンライン用に絞り込まない() {
        let questions = [
            makeQuestion(id: "jh_0001", word: "book", category: .juniorHigh, difficulty: .one),
            makeQuestion(id: "hs_0001", word: "accept", category: .highSchool, difficulty: .five)
        ]

        XCTAssertEqual(questions.matching(category: nil, difficulty: nil).count, 2)
    }

    func test_オンライン対戦設定をデータベース値へ保存して復元する() {
        let original = RoomState.Settings(
            questionCount: 10,
            timeLimit: 20,
            genre: .englishWord,
            wordCategory: .toeic,
            wordDifficulty: .three
        )

        let restored = RoomState.Settings(databaseValue: original.databaseValue)

        XCTAssertEqual(restored.questionCount, 10)
        XCTAssertEqual(restored.timeLimit, 20)
        XCTAssertEqual(restored.genre, .englishWord)
        XCTAssertEqual(restored.wordCategory, .toeic)
        XCTAssertEqual(restored.wordDifficulty, .three)
    }

    func test_分類設定がない旧オンラインルームは全問題を対象にする() {
        let legacySettings = RoomState.Settings(databaseValue: [
            "questionCount": 10,
            "timeLimit": 20,
            "genre": Genre.englishWord.rawValue
        ])

        XCTAssertNil(legacySettings.wordCategory)
        XCTAssertNil(legacySettings.wordDifficulty)
    }

    func test_難易度を5段階の星で表示する() {
        XCTAssertEqual(WordDifficulty.one.starDisplay, "★☆☆☆☆")
        XCTAssertEqual(WordDifficulty.two.starDisplay, "★★☆☆☆")
        XCTAssertEqual(WordDifficulty.three.starDisplay, "★★★☆☆")
        XCTAssertEqual(WordDifficulty.four.starDisplay, "★★★★☆")
        XCTAssertEqual(WordDifficulty.five.starDisplay, "★★★★★")
    }

    func test_代名詞接続詞前置詞を同じ誤答グループで4択にする() throws {
        let minorFunctionWordEntries = [
            makeEntry(id: "test_0001", word: "they", meaning: "彼らは", pos: .pronoun),
            makeEntry(id: "test_0002", word: "because", meaning: "なぜなら", pos: .conjunction),
            makeEntry(id: "test_0003", word: "under", meaning: "〜の下に", pos: .preposition),
            makeEntry(id: "test_0004", word: "although", meaning: "〜だけれども", pos: .conjunction)
        ]
        let nounEntry = makeEntry(
            id: "test_0005",
            word: "company",
            meaning: "会社",
            pos: .noun
        )

        let questions = QuestionSeeder.makeQuestions(
            from: minorFunctionWordEntries + [nounEntry]
        )
        let minorMeanings = Set(minorFunctionWordEntries.map(\.meaning))

        for entry in minorFunctionWordEntries {
            let question = try XCTUnwrap(questions.first { $0.id == entry.id })
            XCTAssertEqual(question.choices.count, 4)
            XCTAssertEqual(Set(question.choices), minorMeanings)
            XCTAssertFalse(question.choices.contains(nounEntry.meaning))
        }
    }

    func test_助動詞は少数機能語の誤答グループに属する() {
        XCTAssertEqual(PartOfSpeech.auxiliary.distractorGroup, .minorFunctionWords)
    }

    func test_収録データは各カテゴリを含みIDと単語が重複しない() throws {
        let entries = try QuestionSeeder.loadEntries()
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "問題IDが重複している")

        for category in WordCategory.allCases {
            let categoryEntries = entries.filter { $0.category == category }
            XCTAssertFalse(categoryEntries.isEmpty, "\(category.displayName)が空")
            XCTAssertEqual(
                Set(categoryEntries.map(\.normalizedWordKey)).count,
                categoryEntries.count,
                "\(category.displayName)内で単語が重複している"
            )
        }
    }

    func test_カテゴリ別のID接頭辞が統一されている() throws {
        let entries = try QuestionSeeder.loadEntries()

        XCTAssertTrue(entries.filter { $0.category == .juniorHigh }.allSatisfy { $0.id.hasPrefix("jh_") })
        XCTAssertTrue(entries.filter { $0.category == .highSchool }.allSatisfy { $0.id.hasPrefix("hs_") })
        // TOEICは銀のフレーズ=tc1_、金のフレーズ=tc2_ でシート別に分かれている
        XCTAssertTrue(entries.filter { $0.category == .toeic }.allSatisfy {
            $0.id.hasPrefix("tc1_") || $0.id.hasPrefix("tc2_")
        })
    }

    func test_旧IDの学習履歴と復習項目を同じ単語の新IDへ引き継ぐ() throws {
        let context = ModelContext(container)
        context.insert(
            Question(
                id: "en_0001",
                genre: .englishWord,
                type: .multipleChoice,
                text: "benefit",
                choices: ["恩恵"],
                answer: "恩恵"
            )
        )
        context.insert(AnswerRecord(questionID: "en_0001", isCorrect: false, mode: .practice))
        context.insert(ReviewItem(questionID: "en_0001"))
        try context.save()

        let versionKey = "questionDataVersion"
        let previousVersion = UserDefaults.standard.object(forKey: versionKey)
        defer {
            if let previousVersion {
                UserDefaults.standard.set(previousVersion, forKey: versionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: versionKey)
            }
        }
        UserDefaults.standard.set(QuestionSeeder.dataVersion - 1, forKey: versionKey)

        QuestionSeeder.seedIfNeeded(context: context)

        let records = try context.fetch(FetchDescriptor<AnswerRecord>())
        let reviewItems = try context.fetch(FetchDescriptor<ReviewItem>())
        XCTAssertEqual(records.map(\.questionID), ["jh_0001"])
        XCTAssertEqual(reviewItems.map(\.questionID), ["jh_0001"])
    }
}
