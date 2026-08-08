import Foundation

/// Realtime Databaseの rooms/{code} スナップショットをデコードした状態(要件 §8.2)
struct RoomState {
    enum Status: String {
        case waiting   // ロビーで待機中
        case playing   // 対戦中
        case finished  // リザルト表示
        case closed    // ホスト退出などで解散
    }

    enum GamePhase: String {
        case question  // 出題中(早押し受付)
        case reveal    // 正解発表中
        case finished  // 全問終了
    }

    struct Player: Identifiable, Equatable {
        let id: String
        let nickname: String
        let score: Int
        let joinedAtMS: Double
    }

    struct QuestionPayload: Equatable {
        let id: String
        let text: String
        let choices: [String]
        let answer: String
    }

    struct Reveal: Equatable {
        let correctAnswer: String
        let scorerID: String?
        let byTimeout: Bool
    }

    /// 文字送り型の回答1件。選択肢を押した瞬間を記録する(要件 §5.1.2)
    struct Answer: Equatable {
        let uid: String
        let choice: String
        /// 押した時刻(サーバータイムスタンプ・ms)。先着はこの値で決まる
        let answeredAtMS: Double
        /// 押した時点で表示されていた文字数。何文字で分かったかの記録に使う
        let visibleCount: Int
    }

    struct Game {
        let questionIndex: Int
        let phase: GamePhase
        let startedAtMS: Double
        let buzzWinner: String?
        /// uid → サーバータイムスタンプ(ms)。押下順キュー(即答型。要件 §5.1.2)
        let buzzQueue: [String: Double]
        /// この問題で誤答済みのuid。再回答できない
        let failedIDs: Set<String>
        let answer: (uid: String, choice: String)?
        /// 文字送り型で届いた回答(押した順)
        let answers: [Answer]
        let reveal: Reveal?
    }

    struct Settings {
        let questionCount: Int
        let timeLimit: TimeInterval
        let genre: Genre
        /// 出題形式(即答型/文字送り型)。ホストが決め、全員に同じ形式で配信される
        let style: QuizStyle
        /// 英単語のカテゴリと難易度。nilは分類設定のない旧ルームとの互換用
        let wordCategory: WordCategory?
        let wordDifficulty: WordDifficulty?

        init(
            questionCount: Int,
            timeLimit: TimeInterval,
            genre: Genre,
            style: QuizStyle = QuizDefaults.style,
            wordCategory: WordCategory? = nil,
            wordDifficulty: WordDifficulty? = nil
        ) {
            self.questionCount = questionCount
            self.timeLimit = timeLimit
            self.genre = genre
            self.style = style
            self.wordCategory = wordCategory
            self.wordDifficulty = wordDifficulty
        }

        /// Realtime Databaseのsettingsへ保存する値
        var databaseValue: [String: Any] {
            var value: [String: Any] = [
                "questionCount": questionCount,
                "timeLimit": timeLimit,
                "genre": genre.rawValue,
                "style": style.rawValue
            ]
            if let wordCategory, let wordDifficulty {
                value["wordCategory"] = wordCategory.rawValue
                value["wordDifficulty"] = wordDifficulty.rawValue
            }
            return value
        }

        init(databaseValue: [String: Any]) {
            questionCount = RoomState.int(databaseValue["questionCount"]) ?? QuizDefaults.questionCount
            timeLimit = RoomState.double(databaseValue["timeLimit"]) ?? QuizDefaults.timeLimit
            genre = Genre(rawValue: databaseValue["genre"] as? String ?? "") ?? .englishWord
            style = QuizStyle(rawValue: databaseValue["style"] as? String ?? "") ?? QuizDefaults.style

            let category = WordCategory(rawValue: databaseValue["wordCategory"] as? String ?? "")
            let difficultyValue = RoomState.int(databaseValue["wordDifficulty"])
            let difficulty = difficultyValue.flatMap(WordDifficulty.init(rawValue:))
            if let category, let difficulty {
                wordCategory = category
                wordDifficulty = difficulty
            } else {
                wordCategory = nil
                wordDifficulty = nil
            }
        }
    }

    let code: String
    let hostID: String
    let status: Status
    let settings: Settings
    /// 入室順に並んだ参加者
    let players: [Player]
    let questions: [QuestionPayload]
    let game: Game?

    /// ローカル(CPU対戦)用に直接組み立てるイニシャライザ
    init(code: String, hostID: String, status: Status, settings: Settings,
         players: [Player], questions: [QuestionPayload], game: Game?) {
        self.code = code
        self.hostID = hostID
        self.status = status
        self.settings = settings
        self.players = players
        self.questions = questions
        self.game = game
    }

    init?(code: String, dict: [String: Any]) {
        guard let hostID = dict["hostID"] as? String,
              let statusRaw = dict["status"] as? String,
              let status = Status(rawValue: statusRaw) else { return nil }

        self.code = code
        self.hostID = hostID
        self.status = status

        let settingsDict = dict["settings"] as? [String: Any] ?? [:]
        self.settings = Settings(databaseValue: settingsDict)

        let playersDict = dict["players"] as? [String: [String: Any]] ?? [:]
        self.players = playersDict.map { uid, value in
            Player(
                id: uid,
                nickname: value["nickname"] as? String ?? "?",
                score: Self.int(value["score"]) ?? 0,
                joinedAtMS: Self.double(value["joinedAt"]) ?? 0
            )
        }
        .sorted { $0.joinedAtMS < $1.joinedAtMS }

        self.questions = (dict["questions"] as? [[String: Any]] ?? []).compactMap { q in
            guard let id = q["id"] as? String,
                  let text = q["text"] as? String,
                  let choices = q["choices"] as? [String],
                  let answer = q["answer"] as? String else { return nil }
            return QuestionPayload(id: id, text: text, choices: choices, answer: answer)
        }

        self.game = Self.parseGame(dict["game"] as? [String: Any])
    }

    private static func parseGame(_ dict: [String: Any]?) -> Game? {
        guard let dict,
              let index = int(dict["questionIndex"]),
              let phaseRaw = dict["phase"] as? String,
              let phase = GamePhase(rawValue: phaseRaw) else { return nil }

        let buzz = dict["buzz"] as? [String: Any] ?? [:]
        let queue = (buzz["queue"] as? [String: Any] ?? [:]).compactMapValues { double($0) }
        let failed = Set((buzz["failed"] as? [String: Any] ?? [:]).keys)

        var answer: (uid: String, choice: String)?
        if let answerDict = dict["answer"] as? [String: Any],
           let uid = answerDict["uid"] as? String,
           let choice = answerDict["choice"] as? String {
            answer = (uid, choice)
        }

        let answers = (dict["answers"] as? [String: [String: Any]] ?? [:])
            .compactMap { uid, value -> Answer? in
                guard let choice = value["choice"] as? String else { return nil }
                return Answer(
                    uid: uid,
                    choice: choice,
                    answeredAtMS: double(value["ts"]) ?? 0,
                    visibleCount: int(value["visibleCount"]) ?? 0
                )
            }
            .sorted { $0.answeredAtMS < $1.answeredAtMS }

        var reveal: Reveal?
        if let revealDict = dict["reveal"] as? [String: Any],
           let correctAnswer = revealDict["correctAnswer"] as? String {
            let scorer = revealDict["scorerID"] as? String
            reveal = Reveal(
                correctAnswer: correctAnswer,
                scorerID: (scorer?.isEmpty ?? true) ? nil : scorer,
                byTimeout: revealDict["byTimeout"] as? Bool ?? false
            )
        }

        return Game(
            questionIndex: index,
            phase: phase,
            startedAtMS: double(dict["startedAt"]) ?? 0,
            buzzWinner: buzz["winner"] as? String,
            buzzQueue: queue,
            failedIDs: failed,
            answer: answer,
            answers: answers,
            reveal: reveal
        )
    }

    private static func int(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }
    private static func double(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
}
