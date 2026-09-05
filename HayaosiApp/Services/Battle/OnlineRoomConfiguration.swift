import Foundation

/// 対戦ホームから作るオンラインルームの前回設定。端末内だけへ保存する。
struct OnlineRoomConfiguration: Equatable {
    static let categoryKey = "onlineRoomCategory"
    static let difficultyKey = "onlineRoomDifficulty"
    static let questionCountKey = "onlineRoomQuestionCount"
    static let timeLimitKey = "onlineRoomTimeLimit"

    static let `default` = OnlineRoomConfiguration(
        category: .juniorHigh,
        difficulty: .one,
        questionCount: QuizDefaults.questionCount,
        timeLimit: QuizDefaults.timeLimit
    )

    var category: WordCategory
    var difficulty: WordDifficulty
    var questionCount: Int
    var timeLimit: TimeInterval

    init(
        category: WordCategory,
        difficulty: WordDifficulty,
        questionCount: Int,
        timeLimit: TimeInterval
    ) {
        self.category = category
        self.difficulty = difficulty
        self.questionCount = questionCount
        self.timeLimit = timeLimit
    }

    init(defaults: UserDefaults = .standard) {
        let fallback = Self.default
        category = WordCategory(
            rawValue: defaults.string(forKey: Self.categoryKey) ?? ""
        ) ?? fallback.category
        difficulty = WordDifficulty(
            rawValue: defaults.integer(forKey: Self.difficultyKey)
        ) ?? fallback.difficulty

        let storedCount = defaults.integer(forKey: Self.questionCountKey)
        questionCount = QuizDefaults.questionCountOptions.contains(storedCount)
            ? storedCount
            : fallback.questionCount

        let storedLimit = defaults.double(forKey: Self.timeLimitKey)
        timeLimit = QuizDefaults.timeLimitOptions.contains(storedLimit)
            ? storedLimit
            : fallback.timeLimit
    }

    /// 既に存在するルームの設定画面を、現在値のまま開くための初期化。
    init(settings: RoomState.Settings) {
        let fallback = Self.default
        category = settings.wordCategory ?? fallback.category
        difficulty = settings.wordDifficulty ?? fallback.difficulty
        questionCount = settings.questionCount
        timeLimit = settings.timeLimit
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(category.rawValue, forKey: Self.categoryKey)
        defaults.set(difficulty.rawValue, forKey: Self.difficultyKey)
        defaults.set(questionCount, forKey: Self.questionCountKey)
        defaults.set(timeLimit, forKey: Self.timeLimitKey)
    }

    func roomSettings(availableQuestionCount: Int) -> RoomState.Settings {
        .init(
            questionCount: min(questionCount, availableQuestionCount),
            timeLimit: timeLimit,
            genre: .englishWord,
            wordCategory: category,
            wordDifficulty: difficulty
        )
    }
}
