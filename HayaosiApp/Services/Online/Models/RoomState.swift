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
        /// 正解者内の回答時刻順。空なら正解者なし
        let correctIDs: [String]
    }

    /// 文字送り型の回答1件。選択肢を押した瞬間を記録する(要件 §5.1.2)
    struct Answer: Equatable {
        let uid: String
        /// 回答した問題番号。遅れて届いた前問の回答を次問へ混ぜないために使う
        let questionIndex: Int
        let choice: String
        /// 押した時刻(サーバータイムスタンプ・ms)。先着はこの値で決まる
        let answeredAtMS: Double
        /// 押した時点で表示されていた文字数。何文字で分かったかの記録に使う
        let visibleCount: Int
    }

    struct Game {
        let questionIndex: Int
        let phase: GamePhase
        /// `startedAtMS` から実際に1問目を始めるまでの猶予(ms)。旧ルームと2問目以降は0
        let startDelayMS: Double
        let startedAtMS: Double
        var effectiveStartedAtMS: Double { startedAtMS + startDelayMS }
        /// この問題で誤答済みのuid。再回答できない
        let failedIDs: Set<String>
        /// 文字送り型で届いた回答(押した順)
        let answers: [Answer]
        let reveal: Reveal?
    }

    struct Settings {
        let questionCount: Int
        let timeLimit: TimeInterval
        let genre: Genre
        /// 英単語のカテゴリと難易度。nilは分類設定のない旧ルームとの互換用
        let wordCategory: WordCategory?
        let wordDifficulty: WordDifficulty?

        init(
            questionCount: Int,
            timeLimit: TimeInterval,
            genre: Genre,
            wordCategory: WordCategory? = nil,
            wordDifficulty: WordDifficulty? = nil
        ) {
            self.questionCount = questionCount
            self.timeLimit = timeLimit
            self.genre = genre
            self.wordCategory = wordCategory
            self.wordDifficulty = wordDifficulty
        }

        /// Realtime Databaseのsettingsへ保存する値
        var databaseValue: [String: Any] {
            var value: [String: Any] = [
                "questionCount": questionCount,
                "timeLimit": timeLimit,
                "genre": genre.rawValue
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
    /// ルームコードが将来再利用されても別ルームと識別する、作成ごとの不変ID。
    /// nilは導入前の旧ルームとFirebaseを使わないCPU対戦だけ。
    let roomInstanceID: String?
    let hostID: String
    let status: Status
    let settings: Settings
    /// 入室順に並んだ参加者
    let players: [Player]
    /// 0...7の固定参加枠。新規playerと同じatomic writeでclaim/releaseする。
    let playerSlots: [Int: String]
    let questions: [QuestionPayload]
    let game: Game?

    func playerSlot(for uid: String) -> Int? {
        playerSlots.first { $0.value == uid }?.key
    }

    var firstAvailablePlayerSlot: Int? {
        (0..<BattleRules.maxPlayers).first { playerSlots[$0] == nil }
    }

    /// ローカル(CPU対戦)用に直接組み立てるイニシャライザ
    init(code: String, roomInstanceID: String? = nil, hostID: String, status: Status, settings: Settings,
         players: [Player], playerSlots: [Int: String] = [:],
         questions: [QuestionPayload], game: Game?) {
        self.code = code
        self.roomInstanceID = roomInstanceID
        self.hostID = hostID
        self.status = status
        self.settings = settings
        self.players = players
        self.playerSlots = playerSlots
        self.questions = questions
        self.game = game
    }

    init?(code: String, dict: [String: Any]) {
        guard let hostID = dict["hostID"] as? String,
              let statusRaw = dict["status"] as? String,
              let status = Status(rawValue: statusRaw) else { return nil }

        self.code = code
        self.roomInstanceID = dict["roomInstanceID"] as? String
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

        self.playerSlots = Self.parsePlayerSlots(dict["playerSlots"])

        self.questions = (dict["questions"] as? [[String: Any]] ?? []).compactMap { q in
            guard let id = q["id"] as? String,
                  let text = q["text"] as? String,
                  let choices = q["choices"] as? [String],
                  let answer = q["answer"] as? String else { return nil }
            return QuestionPayload(id: id, text: text, choices: choices, answer: answer)
        }

        self.game = Self.parseGame(dict["game"] as? [String: Any])
    }

    /// RTDBは0から連続する数値キーを配列として返し、途中に空きがある場合は辞書として返す。
    /// どちらの表現でも同じslot集合へ正規化する。
    private static func parsePlayerSlots(_ value: Any?) -> [Int: String] {
        if let slots = value as? [Any] {
            return Dictionary(uniqueKeysWithValues: slots.enumerated().compactMap { slot, value in
                guard (0..<BattleRules.maxPlayers).contains(slot),
                      let uid = value as? String else { return nil }
                return (slot, uid)
            })
        }
        let slots = value as? [String: Any] ?? [:]
        return Dictionary(uniqueKeysWithValues: slots.compactMap { key, value in
            guard let slot = Int(key), (0..<BattleRules.maxPlayers).contains(slot),
                  let uid = value as? String else { return nil }
            return (slot, uid)
        })
    }

    private static func parseGame(_ dict: [String: Any]?) -> Game? {
        guard let dict,
              let index = int(dict["questionIndex"]),
              let phaseRaw = dict["phase"] as? String,
              let phase = GamePhase(rawValue: phaseRaw) else { return nil }

        // お手付きにも問題番号を持たせる。前問の遅延書き込みがクリア後に届いても、
        // 現在の問題番号と違えば回答不能にはしない。
        let failed = Set((dict["failed"] as? [String: [String: Any]] ?? [:]).compactMap { uid, value in
            int(value["questionIndex"]) == index ? uid : nil
        })

        let answers = (dict["answers"] as? [String: [String: Any]] ?? [:])
            .compactMap { uid, value -> Answer? in
                guard let answerQuestionIndex = int(value["questionIndex"]),
                      answerQuestionIndex == index,
                      let choice = value["choice"] as? String,
                      // ServerValue.timestampはserver確定前のlocal snapshotでは
                      // {".sv":"timestamp"}。0秒の回答へ変換せず、確定値を待つ。
                      let answeredAtMS = double(value["ts"]) else { return nil }
                return Answer(
                    uid: uid,
                    questionIndex: answerQuestionIndex,
                    choice: choice,
                    answeredAtMS: answeredAtMS,
                    visibleCount: int(value["visibleCount"]) ?? 0
                )
            }
            .sorted { $0.answeredAtMS < $1.answeredAtMS }

        var reveal: Reveal?
        if let revealDict = dict["reveal"] as? [String: Any],
           let correctAnswer = revealDict["correctAnswer"] as? String {
            let correctIDs = revealDict["correctIDs"] as? [String] ?? []
            reveal = Reveal(
                correctAnswer: correctAnswer,
                correctIDs: correctIDs
            )
        }

        return Game(
            questionIndex: index,
            phase: phase,
            startDelayMS: double(dict["startDelayMS"]) ?? 0,
            startedAtMS: double(dict["startedAt"]) ?? 0,
            failedIDs: failed,
            answers: answers,
            reveal: reveal
        )
    }

    /// `game`単体のtransaction確定スナップショットを、通常のルーム監視と同じ規則で復元する。
    static func game(databaseValue: [String: Any]) -> Game? {
        parseGame(databaseValue)
    }

    private static func int(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }
    private static func double(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
}
