import Foundation

/// 対戦ホームから作るオンラインルームの前回設定。端末内だけへ保存する。
struct OnlineRoomConfiguration: Equatable {
    static let genreKey = "onlineRoomGenre"
    static let categoryKey = "onlineRoomCategory"
    static let difficultyKey = "onlineRoomDifficulty"
    static let questionCountKey = "onlineRoomQuestionCount"
    static let timeLimitKey = "onlineRoomTimeLimit"

    static let `default` = OnlineRoomConfiguration(
        genre: .englishWord,
        category: .juniorHigh,
        difficulty: .one,
        questionCount: QuizDefaults.questionCount,
        timeLimit: QuizDefaults.timeLimit
    )

    var genre: Genre
    var category: StudyCategory
    var difficulty: StudyDifficulty
    var questionCount: Int
    var timeLimit: TimeInterval

    init(
        genre: Genre,
        category: StudyCategory,
        difficulty: StudyDifficulty,
        questionCount: Int,
        timeLimit: TimeInterval
    ) {
        self.genre = genre
        self.category = category
        self.difficulty = difficulty
        self.questionCount = questionCount
        self.timeLimit = timeLimit
    }

    init(defaults: UserDefaults = .standard) {
        let fallback = Self.default
        let storedCategory = StudyCategory(
            rawValue: defaults.string(forKey: Self.categoryKey) ?? ""
        ) ?? fallback.category
        // 保存済みのジャンルとカテゴリが食い違っていたら、カテゴリ側を正とする
        genre = storedCategory.genre
        category = storedCategory
        difficulty = StudyDifficulty(
            rawValue: defaults.integer(forKey: Self.difficultyKey)
        ) ?? fallback.difficulty

        let storedCount = defaults.integer(forKey: Self.questionCountKey)
        questionCount = QuizDefaults.questionCountOptions.contains(storedCount)
            ? storedCount
            : fallback.questionCount

        let storedLimit = defaults.double(forKey: Self.timeLimitKey)
        timeLimit = QuizDefaults.timeLimitOptions(for: category).contains(storedLimit)
            ? storedLimit
            : category.defaultTimeLimit
    }

    /// 既に存在するルームの設定画面を、現在値のまま開くための初期化。
    init(settings: RoomState.Settings) {
        let fallback = Self.default
        category = settings.wordCategory ?? fallback.category
        genre = (settings.wordCategory ?? fallback.category).genre
        difficulty = settings.wordDifficulty ?? fallback.difficulty
        questionCount = settings.questionCount
        timeLimit = settings.timeLimit
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(genre.rawValue, forKey: Self.genreKey)
        defaults.set(category.rawValue, forKey: Self.categoryKey)
        defaults.set(difficulty.rawValue, forKey: Self.difficultyKey)
        defaults.set(questionCount, forKey: Self.questionCountKey)
        defaults.set(timeLimit, forKey: Self.timeLimitKey)
    }

    /// ジャンルを変えると、そのジャンルのカテゴリと既定の制限時間へ揃える
    mutating func changeGenre(to newGenre: Genre) {
        guard newGenre != genre, let first = newGenre.categories.first else { return }
        genre = newGenre
        category = first
        timeLimit = first.defaultTimeLimit
    }

    func roomSettings(availableQuestionCount: Int) -> RoomState.Settings {
        .init(
            questionCount: min(questionCount, availableQuestionCount),
            timeLimit: timeLimit,
            genre: genre,
            wordCategory: category,
            wordDifficulty: difficulty
        )
    }
}
