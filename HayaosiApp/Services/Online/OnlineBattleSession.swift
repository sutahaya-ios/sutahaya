import Foundation
import Observation
import SwiftData
import FirebaseDatabase

/// 通信対戦セッション(要件 §5.1)
/// ルームの作成・入室・観測と、プレイヤー操作(早押し・回答)を担当する。
/// 進行の権威はホスト端末(OnlineBattleSession+Host.swift)が持つ。
@MainActor
@Observable
final class OnlineBattleSession: BattleSession {
    enum SessionError: LocalizedError {
        case databaseUnavailable
        case roomNotFound
        case roomFull
        case alreadyStarted
        case codeGenerationFailed

        var errorDescription: String? {
            switch self {
            case .databaseUnavailable:
                return "通信対戦が未設定です(FIREBASE_SETUP.md を参照)"
            case .roomNotFound:
                return "ルームが見つかりません。コードを確認してください"
            case .roomFull:
                return "このルームは満員です(最大\(BattleRules.maxPlayers)人)"
            case .alreadyStarted:
                return "このルームは対戦中のため入室できません"
            case .codeGenerationFailed:
                return "ルームコードの発行に失敗しました。もう一度お試しください"
            }
        }
    }

    let myID: String
    let nickname: String
    private(set) var roomCode = ""
    private(set) var isHost = false
    private(set) var state: RoomState?
    var lastError: String?
    /// 自分が回答に関与した問題の正誤(復習リスト反映用)。questionID → isCorrect
    private(set) var myResultsByQuestion: [String: Bool] = [:]

    private let roomsRef: DatabaseReference
    private var observerHandle: DatabaseHandle?
    private var hasSavedResults = false
    private var hasLeft = false

    // MARK: ホスト進行管理(OnlineBattleSession+Host.swift から使用)
    var questionTimerTask: Task<Void, Never>?
    var answerTimerTask: Task<Void, Never>?
    var revealTask: Task<Void, Never>?
    var timedQuestion: (index: Int, startedAtMS: Double)?
    var answerTimerKey: String?
    var revealScheduledIndex: Int?
    var isEvaluatingAnswer = false

    var roomRef: DatabaseReference { roomsRef.child(roomCode) }

    var isOnline: Bool { true }

    init(myID: String, nickname: String) throws {
        guard OnlineService.isDatabaseAvailable else { throw SessionError.databaseUnavailable }
        self.myID = myID
        self.nickname = nickname
        self.roomsRef = Database.database().reference().child("rooms")
    }

    // MARK: - ルーム作成・入室・退出

    func createRoom(settings: RoomState.Settings) async throws {
        for _ in 0..<BattleRules.createAttempts {
            let code = String(format: "%0\(BattleRules.codeDigits)d", Int.random(in: 0...9999))
            let snapshot = try await roomsRef.child(code).getData()
            if snapshot.exists() { continue }

            let value: [String: Any] = [
                "hostID": myID,
                "status": RoomState.Status.waiting.rawValue,
                "createdAt": ServerValue.timestamp(),
                "settings": [
                    "questionCount": settings.questionCount,
                    "timeLimit": settings.timeLimit,
                    "genre": settings.genre.rawValue,
                    "style": settings.style.rawValue
                ],
                "players": [
                    myID: ["nickname": nickname, "score": 0, "joinedAt": ServerValue.timestamp()]
                ]
            ]
            try await roomsRef.child(code).setValue(value)
            roomCode = code
            isHost = true
            // ホストが切断したらルームを解散扱いにする
            try await roomsRef.child(code).child("status")
                .onDisconnectSetValue(RoomState.Status.closed.rawValue)
            startObserving()
            return
        }
        throw SessionError.codeGenerationFailed
    }

    func joinRoom(code: String) async throws {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = try await roomsRef.child(normalized).getData()
        guard snapshot.exists(),
              let dict = snapshot.value as? [String: Any],
              let current = RoomState(code: normalized, dict: dict) else {
            throw SessionError.roomNotFound
        }
        guard current.status == .waiting else { throw SessionError.alreadyStarted }
        guard current.players.count < BattleRules.maxPlayers else { throw SessionError.roomFull }

        roomCode = normalized
        isHost = (current.hostID == myID)
        let playerRef = roomRef.child("players/\(myID)")
        try await playerRef.setValue([
            "nickname": nickname,
            "score": 0,
            "joinedAt": ServerValue.timestamp()
        ])
        try await playerRef.onDisconnectRemoveValue()
        startObserving()
    }

    /// 退出。ホストはルームを解散し、参加者は自分だけ抜ける
    func leave() {
        guard !hasLeft else { return }
        hasLeft = true
        stopHostTasks()
        stopObserving()
        guard !roomCode.isEmpty else { return }
        if isHost {
            roomRef.child("status").setValue(RoomState.Status.closed.rawValue)
        } else {
            roomRef.child("players/\(myID)").removeValue()
        }
    }

    // MARK: - ホスト操作

    /// 対戦開始。選択肢は全端末で同じ並びになるようホストがシャッフルして配信する
    func startGame(questions: [Question]) async {
        guard isHost, let state, state.players.count >= BattleRules.minPlayersToStart else { return }
        let payload: [[String: Any]] = questions.map { question in
            [
                "id": question.id,
                "text": question.text,
                "choices": question.choices.shuffled(),
                "answer": question.answer
            ]
        }
        do {
            try await roomRef.updateChildValues([
                "status": RoomState.Status.playing.rawValue,
                "questions": payload,
                "game": [
                    "questionIndex": 0,
                    "phase": RoomState.GamePhase.question.rawValue,
                    "startedAt": ServerValue.timestamp()
                ]
            ])
        } catch {
            lastError = "対戦の開始に失敗しました"
            print("対戦開始に失敗: \(error)")
        }
    }

    /// 再戦:スコアをリセットしてロビーに戻す
    func rematch() async {
        guard isHost, let state else { return }
        var updates: [String: Any] = [
            "status": RoomState.Status.waiting.rawValue,
            "game": NSNull(),
            "questions": NSNull()
        ]
        for player in state.players {
            updates["players/\(player.id)/score"] = 0
        }
        do {
            try await roomRef.updateChildValues(updates)
            myResultsByQuestion = [:]
            hasSavedResults = false
        } catch {
            lastError = "再戦の準備に失敗しました"
            print("再戦の準備に失敗: \(error)")
        }
    }

    // MARK: - プレイヤー操作

    /// 早押し。winnerへのトランザクションで「最初の1人」を原子的に確定し(要件 §5.1.2)、
    /// 併せて押下順キューにも記録する(誤答時の回答権移行用)
    func buzz() {
        guard let game = currentGame,
              game.phase == .question,
              game.buzzWinner == nil,
              !game.failedIDs.contains(myID) else { return }

        let uid = myID
        roomRef.child("game/buzz/winner").runTransactionBlock { currentData in
            if currentData.value == nil || currentData.value is NSNull {
                currentData.value = uid
            }
            return TransactionResult.success(withValue: currentData)
        }
        roomRef.child("game/buzz/queue/\(uid)").setValue(ServerValue.timestamp())
    }

    func submitAnswer(_ choice: String) {
        guard let game = currentGame, game.buzzWinner == myID, game.phase == .question else { return }
        roomRef.child("game/answer").setValue(["uid": myID, "choice": choice])
    }

    // MARK: - 状態参照ヘルパー
    // currentQuestion / player(for:) / remainingTime(at:) は BattleSession の共通実装を使う

    private var currentGame: RoomState.Game? {
        guard let state, state.status == .playing else { return nil }
        return state.game
    }

    // MARK: - 観測

    private func startObserving() {
        observerHandle = roomRef.observe(.value) { [weak self] snapshot in
            MainActor.assumeIsolated {
                self?.apply(snapshot: snapshot)
            }
        }
    }

    private func stopObserving() {
        if let observerHandle {
            roomRef.removeObserver(withHandle: observerHandle)
        }
        observerHandle = nil
    }

    private func apply(snapshot: DataSnapshot) {
        guard snapshot.exists(),
              let dict = snapshot.value as? [String: Any],
              let newState = RoomState(code: roomCode, dict: dict) else {
            state = nil
            return
        }
        state = newState
        captureMyResults(from: newState)
        if isHost {
            hostReact(to: newState)
        }
    }

    /// 自分が関与した問題の正誤を記録する(正解発表・誤答マークから拾う)
    private func captureMyResults(from state: RoomState) {
        guard let game = state.game,
              state.questions.indices.contains(game.questionIndex) else { return }
        let questionID = state.questions[game.questionIndex].id

        if game.failedIDs.contains(myID) {
            myResultsByQuestion[questionID] = false
        }
        if game.reveal?.scorerID == myID {
            myResultsByQuestion[questionID] = true
        }
    }

    /// 対戦終了時に一度だけ、正誤履歴と復習リストへ反映する(要件 §5.4)
    func saveResultsIfNeeded(context: ModelContext) {
        guard !hasSavedResults, state?.status == .finished else { return }
        hasSavedResults = true
        ResultRecorder.record(
            results: myResultsByQuestion.map { ($0.key, $0.value) },
            mode: .battle,
            context: context
        )
    }
}
