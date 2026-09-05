import Foundation
import Observation
import SwiftData
import FirebaseDatabase

enum RTDBJoinRetryPolicy {
    static let acceptOperationBudget: Duration = .seconds(6)
    static let connectionWait: Duration = .seconds(3)
    static let offlineReadRetryDelay: Duration = .milliseconds(250)
    static let transientJoinRetryDelay: Duration = .milliseconds(250)
    static let maxOfflineReadRetries = 1
    static let maxTransientJoinRetries = 12

    /// Firebase DatabaseのgetData()が、接続前かつcacheなしの場合だけ返す一時エラー。
    static func isTransientOffline(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == "com.firebase.core"
            && error.code == 1
            && error.localizedDescription.contains(
                "client offline with no active listeners and no matching disk cache entries"
            )
    }

    /// waitingのroom取得直後、ホストの一時切断によるclosed→復元と競合したjoinだけを再試行する。
    static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == "com.firebase"
            && error.code == 1
    }
}

enum HostDisconnectAction: Equatable {
    case apply
    case delayClosure
    case restore(RoomState.Status)
}

enum HostDisconnectPolicy {
    static func action(
        incomingStatus: RoomState.Status,
        isHost: Bool,
        hasLeft: Bool,
        lastActiveStatus: RoomState.Status?
    ) -> HostDisconnectAction {
        guard incomingStatus == .closed, !hasLeft else { return .apply }
        if isHost, let lastActiveStatus, lastActiveStatus != .closed {
            return .restore(lastActiveStatus)
        }
        return .delayClosure
    }
}

/// 通信対戦セッション(要件 §5.1)
/// ルームの作成・入室・観測と、プレイヤー操作(早押し・回答)を担当する。
/// 進行の権威はホスト端末(OnlineBattleSession+Host.swift)が持つ。
@MainActor
@Observable
final class OnlineBattleSession: NPCManageableBattleSession {
    private static let hostDisconnectGraceNanoseconds: UInt64 = 3_000_000_000

    enum SessionError: LocalizedError {
        case databaseUnavailable
        case roomNotFound
        case roomFull
        case alreadyStarted
        case roomInstanceChanged
        case databaseConnectionTimedOut
        case codeGenerationFailed
        case settingsUnavailable

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
            case .roomInstanceChanged:
                return "招待されたルームは終了しています"
            case .databaseConnectionTimedOut:
                return "通信の準備に時間がかかっています。もう一度お試しください"
            case .codeGenerationFailed:
                return "ルームコードの発行に失敗しました。もう一度お試しください"
            case .settingsUnavailable:
                return "待機中のホストだけが対戦設定を変更できます"
            }
        }
    }

    let myID: String
    let nickname: String
    private(set) var roomCode = ""
    private(set) var isHost = false
    private(set) var isStartingMatch = false
    private(set) var state: RoomState?
    var lastError: String?
    /// 自分が回答に関与した問題の正誤(復習リスト反映用)。questionID → isCorrect
    private(set) var myResultsByQuestion: [String: Bool] = [:]
    var wrongQuestionIDs: Set<String> {
        Set(myResultsByQuestion.compactMap { questionID, isCorrect in
            isCorrect ? nil : questionID
        })
    }

    private let roomsRef: DatabaseReference
    private let serverTimeOffsetRef: DatabaseReference
    private var observerHandle: DatabaseHandle?
    private var serverTimeOffsetObserverHandle: DatabaseHandle?
    private var hasSavedResults = false
    private var hasLeft = false
    private var lastActiveStatus: RoomState.Status?
    private var pendingClosureTask: Task<Void, Never>?
    private var hostRecoveryTask: Task<Void, Never>?
    private var joinedPlayerSlot: Int?
    private(set) var didCreatePlayerDuringLatestJoin = false
    private var pendingCPUProfileIDs: Set<String> = []
    private var pendingCPUSlots: Set<Int> = []

    /// `.info/serverTimeOffset`で補正したFirebaseサーバー時刻 - 端末時刻(ms)。
    private(set) var battleClockOffsetMS: Double = 0

    // MARK: ホスト進行管理(OnlineBattleSession+Host.swift から使用)
    var questionTimerTask: Task<Void, Never>?
    var revealTask: Task<Void, Never>?
    var timedQuestion: (index: Int, effectiveStartedAtMS: Double, clockOffsetMS: Double)?
    var revealScheduledIndex: Int?
    /// 採点済みの問題。スナップショットが複数回届いても得点を二重加算しないためのマーカー
    var scoredQuestionIndex: Int?
    /// 問題を始めた時点の得点。回答が届くたびに「この値+確定した増減」へ置き直すため保持する
    var questionBaseScores: (index: Int, scores: [String: Int])?
    /// ホストの採点・問題送りをFirebaseへ書く順番。前問の遅延書き込みが次問へ追い越さないよう直列化する
    var hostWriteTask: Task<Void, Never>?
    /// 回答受付のtransaction終了から最終結果の確定書き込みまでを直列に行う
    var questionFinalizationTask: Task<Void, Never>?
    var scheduledCPUQuestion: (index: Int, effectiveStartedAtMS: Double)?
    var cpuAnswerTasks: [String: Task<Void, Never>] = [:]
    var participatingCPUIds: Set<String> = []
    let cpuAnswerStrategy = CPUAnswerStrategy()

    var roomRef: DatabaseReference { roomsRef.child(roomCode) }

    var isOnline: Bool { true }

    var cpuProfiles: [CPUProfile] {
        state?.players.compactMap { player in
            CPUProfile.roster.first { $0.id == player.id }
        } ?? []
    }

    init(myID: String, nickname: String) throws {
        guard OnlineService.isDatabaseAvailable else { throw SessionError.databaseUnavailable }
        self.myID = myID
        self.nickname = ProfileInputPolicy.normalizedNickname(nickname)
        self.roomsRef = Database.database().reference().child("rooms")
        self.serverTimeOffsetRef = Database.database().reference(withPath: ".info/serverTimeOffset")
    }

    // MARK: - ルーム作成・入室・退出

    func createRoom(settings: RoomState.Settings) async throws {
        let roomInstanceID = UUID().uuidString.lowercased()
        for _ in 0..<BattleRules.createAttempts {
            let code = String(format: "%0\(BattleRules.codeDigits)d", Int.random(in: 0...9999))
            let snapshot = try await roomsRef.child(code).getData()
            if snapshot.exists() { continue }

            let value: [String: Any] = [
                "roomInstanceID": roomInstanceID,
                "hostID": myID,
                "status": RoomState.Status.waiting.rawValue,
                "createdAt": ServerValue.timestamp(),
                "settings": settings.databaseValue,
                "playerSlots": ["0": myID],
                "players": [
                    myID: [
                        "nickname": nickname,
                        "score": 0,
                        "joinedAt": ServerValue.timestamp(),
                        "roomInstanceID": roomInstanceID,
                        "slot": 0
                    ]
                ]
            ]
            try await roomsRef.child(code).setValue(value)
            roomCode = code
            isHost = true
            joinedPlayerSlot = 0
            lastActiveStatus = .waiting
            // ホストが切断したらルームを解散扱いにする
            try await roomsRef.child(code).child("status")
                .onDisconnectSetValue(RoomState.Status.closed.rawValue)
            startObserving()
            return
        }
        throw SessionError.codeGenerationFailed
    }

    func joinRoom(
        code: String,
        expectedRoomInstanceID: String? = nil,
        operationDeadline: ContinuousClock.Instant? = nil
    ) async throws {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetRoomRef = roomsRef.child(normalized)
        let deadline = operationDeadline
            ?? ContinuousClock.now.advanced(by: RTDBJoinRetryPolicy.acceptOperationBudget)
        var offlineReadRetriesRemaining = RTDBJoinRetryPolicy.maxOfflineReadRetries
        didCreatePlayerDuringLatestJoin = false

        try ensureJoinCanProceed(before: deadline)
        try await waitForDatabaseConnection(before: deadline)

        // slot競合時は最新roomを読み直し、別の空き枠で再試行する。
        for _ in 0...BattleRules.maxPlayers {
            let snapshot = try await getRoomSnapshot(
                from: targetRoomRef,
                before: deadline,
                offlineReadRetriesRemaining: &offlineReadRetriesRemaining
            )
            guard snapshot.exists(),
                  let value = snapshot.value as? [String: Any],
                  let current = RoomState(code: normalized, dict: value) else {
                throw SessionError.roomNotFound
            }
            try validateRoomIdentity(current, expectedRoomInstanceID: expectedRoomInstanceID)

            if current.players.contains(where: { $0.id == myID }) {
                let existingSlot = current.playerSlot(for: myID)
                try await finishJoiningRoom(current, playerSlot: existingSlot)
                return
            }

            guard current.status == .waiting else { throw SessionError.alreadyStarted }
            guard let freeSlot = current.firstAvailablePlayerSlot else {
                throw SessionError.roomFull
            }
            let instanceID = expectedRoomInstanceID ?? current.roomInstanceID
            var playerValue: [String: Any] = [
                "nickname": nickname,
                "score": 0,
                "joinedAt": ServerValue.timestamp(),
                "slot": freeSlot
            ]
            if let instanceID {
                playerValue["roomInstanceID"] = instanceID
            }

            do {
                var transientJoinRetriesRemaining = RTDBJoinRetryPolicy.maxTransientJoinRetries
                while true {
                    try ensureJoinCanProceed(before: deadline)
                    do {
                        // 本番RTDB Rulesでは別枝を相互参照するatomic createが循環拒否になる。
                        // 先にslotを予約し、その予約を根拠にplayerを作成する。
                        let slotRef = targetRoomRef.child("playerSlots/\(freeSlot)")
                        try await slotRef.setValue(myID)
                        do {
                            try await targetRoomRef.child("players/\(myID)").setValue(playerValue)
                        } catch {
                            _ = try? await slotRef.removeValue()
                            throw error
                        }
                        break
                    } catch {
                        guard transientJoinRetriesRemaining > 0,
                              RTDBJoinRetryPolicy.isPermissionDenied(error) else {
                            throw error
                        }
                        transientJoinRetriesRemaining -= 1
                        try await Task.sleep(for: RTDBJoinRetryPolicy.transientJoinRetryDelay)
                    }
                }
                didCreatePlayerDuringLatestJoin = true
                try await finishJoiningRoom(current, playerSlot: freeSlot)
                if ContinuousClock.now >= deadline {
                    // claim lease後まで遅延した参加を残さない。書き込み順にjoinの後でcleanupされる。
                    leave()
                    throw SessionError.databaseConnectionTimedOut
                }
                return
            } catch {
                if error is SessionError { throw error }
                guard let latestSnapshot = try? await targetRoomRef.getData(),
                      let latestValue = latestSnapshot.value as? [String: Any],
                      let latest = RoomState(code: normalized, dict: latestValue) else {
                    throw error
                }
                try validateRoomIdentity(latest, expectedRoomInstanceID: expectedRoomInstanceID)
                if latest.players.contains(where: { $0.id == myID }) {
                    continue
                }
                guard latest.status == .waiting else { throw SessionError.alreadyStarted }
                guard latest.playerSlots.count < BattleRules.maxPlayers else {
                    throw SessionError.roomFull
                }
                if latest.playerSlots[freeSlot] != nil {
                    continue
                }
                throw error
            }
        }
        throw SessionError.roomFull
    }

    private func ensureJoinCanProceed(before deadline: ContinuousClock.Instant) throws {
        guard ContinuousClock.now < deadline else {
            throw SessionError.databaseConnectionTimedOut
        }
    }

    private func waitForDatabaseConnection(
        before operationDeadline: ContinuousClock.Instant
    ) async throws {
        let now = ContinuousClock.now
        guard now < operationDeadline else {
            throw SessionError.databaseConnectionTimedOut
        }
        let connectionDeadline = min(
            operationDeadline,
            now.advanced(by: RTDBJoinRetryPolicy.connectionWait)
        )
        let waitDuration = now.duration(to: connectionDeadline)
        let connectedRef = Database.database().reference(withPath: ".info/connected")

        try await withCheckedThrowingContinuation { continuation in
            var didFinish = false
            var observerHandle: DatabaseHandle?
            var timeoutTask: Task<Void, Never>?

            let finish: (Result<Void, Error>) -> Void = { result in
                guard !didFinish else { return }
                didFinish = true
                if let observerHandle {
                    connectedRef.removeObserver(withHandle: observerHandle)
                }
                timeoutTask?.cancel()
                continuation.resume(with: result)
            }

            observerHandle = connectedRef.observe(.value, with: { snapshot in
                MainActor.assumeIsolated {
                    guard (snapshot.value as? NSNumber)?.boolValue == true else { return }
                    finish(.success(()))
                }
            }, withCancel: { error in
                MainActor.assumeIsolated {
                    finish(.failure(error))
                }
            })

            if didFinish, let observerHandle {
                connectedRef.removeObserver(withHandle: observerHandle)
            } else {
                timeoutTask = Task { @MainActor in
                    try? await Task.sleep(for: waitDuration)
                    guard !Task.isCancelled else { return }
                    finish(.failure(SessionError.databaseConnectionTimedOut))
                }
            }
        }
    }

    private func getRoomSnapshot(
        from reference: DatabaseReference,
        before deadline: ContinuousClock.Instant,
        offlineReadRetriesRemaining: inout Int
    ) async throws -> DataSnapshot {
        while true {
            try ensureJoinCanProceed(before: deadline)
            do {
                return try await reference.getData()
            } catch {
                guard offlineReadRetriesRemaining > 0,
                      RTDBJoinRetryPolicy.isTransientOffline(error) else {
                    throw error
                }
                offlineReadRetriesRemaining -= 1
                try await waitForDatabaseConnection(before: deadline)
                try await Task.sleep(for: RTDBJoinRetryPolicy.offlineReadRetryDelay)
            }
        }
    }

    private func validateRoomIdentity(
        _ room: RoomState,
        expectedRoomInstanceID: String?
    ) throws {
        guard room.status != .closed else { throw SessionError.roomNotFound }
        if let expectedRoomInstanceID,
           room.roomInstanceID != expectedRoomInstanceID {
            throw SessionError.roomInstanceChanged
        }
    }

    private func finishJoiningRoom(_ room: RoomState, playerSlot: Int?) async throws {
        roomCode = room.code
        isHost = room.hostID == myID
        joinedPlayerSlot = playerSlot
        lastActiveStatus = room.status
        if isHost {
            try await roomRef.child("status").onDisconnectSetValue(RoomState.Status.closed.rawValue)
        } else if let playerSlot {
            try await roomRef.onDisconnectUpdateChildValues([
                "playerSlots/\(playerSlot)": NSNull(),
                "players/\(myID)": NSNull()
            ])
        } else {
            // 導入前の旧ルームへ再接続する場合だけ、旧schemaのcleanupを維持する。
            try await roomRef.child("players/\(myID)").onDisconnectRemoveValue()
        }
        startObserving()
    }

    /// 退出。ホストはルームを解散し、参加者は自分だけ抜ける
    func leave() {
        guard !hasLeft else { return }
        hasLeft = true
        isStartingMatch = false
        stopHostTasks()
        stopObserving()
        guard !roomCode.isEmpty else { return }
        if isHost {
            roomRef.child("status").setValue(RoomState.Status.closed.rawValue)
        } else if let joinedPlayerSlot {
            roomRef.updateChildValues([
                "playerSlots/\(joinedPlayerSlot)": NSNull(),
                "players/\(myID)": NSNull()
            ])
        } else {
            roomRef.child("players/\(myID)").removeValue()
        }
    }

    // MARK: - ホスト操作

    /// 対戦開始。選択肢は全端末で同じ並びになるようホストがシャッフルして配信する
    func startGame(questions: [Question]) async {
        guard isHost, let state, state.players.count >= BattleRules.minPlayersToStart else { return }
        isStartingMatch = true
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
                    "startDelayMS": BattleRules.matchStartDelayMS,
                    "startedAt": ServerValue.timestamp()
                ]
            ])
        } catch {
            isStartingMatch = false
            lastError = "対戦の開始に失敗しました"
            OnlineService.debugLog("対戦開始に失敗: \(error)")
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
            OnlineService.debugLog("再戦の準備に失敗: \(error)")
        }
    }

    func updateSettings(_ settings: RoomState.Settings) async throws {
        guard isHost, state?.status == .waiting else {
            throw SessionError.settingsUnavailable
        }
        try await roomRef.child("settings").setValue(settings.databaseValue)
    }

    /// hostが待機中ルームの空きslotへ既存NPCを追加する。slot予約とplayer作成は
    /// 人間のjoinと同じ順序にし、同時参加でも合計8人を超えないようにする。
    func addCPU(_ profile: CPUProfile) {
        guard isHost,
              let state,
              state.status == .waiting,
              CPUProfile.roster.contains(where: { $0.id == profile.id }),
              !state.players.contains(where: { $0.id == profile.id }),
              !pendingCPUProfileIDs.contains(profile.id),
              state.players.count + pendingCPUProfileIDs.count < BattleRules.maxPlayers,
              let roomInstanceID = state.roomInstanceID,
              let slot = (0..<BattleRules.maxPlayers).first(where: {
                  state.playerSlots[$0] == nil && !pendingCPUSlots.contains($0)
              }) else { return }

        pendingCPUProfileIDs.insert(profile.id)
        pendingCPUSlots.insert(slot)
        Task { [weak self] in
            await self?.addCPU(profile, slot: slot, roomInstanceID: roomInstanceID)
        }
    }

    private func addCPU(_ profile: CPUProfile, slot: Int, roomInstanceID: String) async {
        defer {
            pendingCPUProfileIDs.remove(profile.id)
            pendingCPUSlots.remove(slot)
        }

        let slotRef = roomRef.child("playerSlots/\(slot)")
        do {
            try await slotRef.setValue(profile.id)
            do {
                try await roomRef.child("players/\(profile.id)").setValue([
                    "nickname": profile.nickname,
                    "score": 0,
                    "joinedAt": ServerValue.timestamp(),
                    "roomInstanceID": roomInstanceID,
                    "slot": slot
                ])
            } catch {
                _ = try? await slotRef.removeValue()
                throw error
            }
        } catch {
            lastError = "NPCを追加できませんでした"
            OnlineService.debugLog("NPCの追加に失敗: \(error)")
        }
    }

    /// hostだけが、待機中ルームから既存NPCとそのslotを同時に外す。
    func removeCPU(id: String) {
        guard isHost,
              let state,
              state.status == .waiting,
              CPUProfile.roster.contains(where: { $0.id == id }),
              state.players.contains(where: { $0.id == id }),
              let slot = state.playerSlot(for: id) else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await roomRef.updateChildValues([
                    "playerSlots/\(slot)": NSNull(),
                    "players/\(id)": NSNull()
                ])
            } catch {
                lastError = "NPCを削除できませんでした"
                OnlineService.debugLog("NPCの削除に失敗: \(error)")
            }
        }
    }

    // MARK: - プレイヤー操作

    /// 回答を送る。
    /// 文字送り型は選択肢を押した瞬間が回答なので、押下時刻(サーバー時刻)と表示文字数を一緒に残す。
    /// 先着はサーバー時刻で決まるため、端末の時計のずれに影響されない
    func submitAnswer(_ choice: String, visibleCount: Int) {
        submitAnswer(choice, visibleCount: visibleCount) { _ in }
    }

    /// Firebase writeの正式拒否と、server timestamp／host採点の確定待ちを分けて返す。
    func submitAnswer(
        _ choice: String,
        visibleCount: Int,
        completion: @escaping (BattleAnswerSubmissionOutcome) -> Void
    ) {
        guard let state, state.status == .playing,
              let game = state.game, game.phase == .question else {
            completion(.rejected)
            return
        }
        let nowMS = battleTimeMS(at: .now)
        let deadlineMS = game.effectiveStartedAtMS + state.settings.timeLimit * 1_000
        guard nowMS >= game.effectiveStartedAtMS, nowMS <= deadlineMS else {
            completion(.rejected)
            return
        }

        guard canAnswerNow else {
            completion(.rejected)
            return
        }
        let questionIndex = game.questionIndex
        let timeLimit = state.settings.timeLimit
        let participantIDs = state.players.map(\.id)
        Task { [weak self] in
            guard let self else {
                completion(.rejected)
                return
            }
            let answerRef = roomRef.child("game/answers/\(myID)")
            do {
                try await answerRef.setValue([
                    "questionIndex": questionIndex,
                    "choice": choice,
                    "ts": ServerValue.timestamp(),
                    "visibleCount": visibleCount
                ])
            } catch {
                lastError = "回答を送信できませんでした"
                OnlineService.debugLog("回答の送信に失敗: \(error)")
                completion(.rejected)
                return
            }

            do {
                let gameSnapshot = try await roomRef.child("game").getData()
                guard let gameValue = gameSnapshot.value as? [String: Any],
                      let savedGame = RoomState.game(databaseValue: gameValue),
                      savedGame.questionIndex == questionIndex else {
                    // writeは成功済み。snapshotの欠落・世代遷移だけでは拒否を証明できない。
                    completion(.awaitingHostResult)
                    return
                }
                let confirmation = BattleAnswerAcceptance.submissionConfirmation(
                    in: savedGame,
                    uid: self.myID,
                    timeLimit: timeLimit,
                    participantIDs: participantIDs
                )
                // 出題中のreadに回答がまだ現れない場合は観測反映待ちであり、
                // write失敗や期限切れとして赤いエラーを出さない。
                switch confirmation {
                case .accepted, .pending:
                    completion(.awaitingHostResult)
                case .rejected:
                    completion(.rejected)
                }
            } catch {
                // 回答write成功後の確認read失敗は、hostのlistener結果を待てばよい。
                OnlineService.debugLog("回答の受理確認を待機: \(error)")
                completion(.awaitingHostResult)
            }
        }
    }

    // MARK: - 状態参照ヘルパー
    // currentQuestion / player(for:) / remainingTime(at:) は BattleSession の共通実装を使う

    func acceptedAnswers(state: RoomState, game: RoomState.Game) -> [RoomState.Answer] {
        BattleAnswerAcceptance.acceptedAnswers(
            in: game,
            timeLimit: state.settings.timeLimit,
            participantIDs: state.players.map(\.id)
        )
    }

    // MARK: - 観測

    private func startObserving() {
        startObservingServerTimeOffset()
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
        if let serverTimeOffsetObserverHandle {
            serverTimeOffsetRef.removeObserver(withHandle: serverTimeOffsetObserverHandle)
        }
        serverTimeOffsetObserverHandle = nil
        pendingClosureTask?.cancel()
        pendingClosureTask = nil
        hostRecoveryTask?.cancel()
        hostRecoveryTask = nil
    }

    private func startObservingServerTimeOffset() {
        guard serverTimeOffsetObserverHandle == nil else { return }
        serverTimeOffsetObserverHandle = serverTimeOffsetRef.observe(.value) { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let offset = snapshot.value as? NSNumber else { return }
                guard let self else { return }
                let newOffsetMS = offset.doubleValue
                guard self.battleClockOffsetMS != newOffsetMS else { return }
                self.battleClockOffsetMS = newOffsetMS
                if self.isHost, let state = self.state {
                    self.hostReact(to: state)
                }
            }
        }
    }

    private func apply(snapshot: DataSnapshot) {
        guard snapshot.exists(),
              let dict = snapshot.value as? [String: Any],
              let newState = RoomState(code: roomCode, dict: dict) else {
            state = nil
            return
        }

        switch HostDisconnectPolicy.action(
            incomingStatus: newState.status,
            isHost: isHost,
            hasLeft: hasLeft,
            lastActiveStatus: lastActiveStatus
        ) {
        case .apply:
            apply(state: newState)
        case .delayClosure:
            scheduleClosureConfirmation(newState)
        case .restore(let status):
            recoverHostRoom(to: status)
        }
    }

    private func apply(state newState: RoomState) {
        if newState.status != .waiting {
            isStartingMatch = false
        }
        if newState.status != .closed {
            pendingClosureTask?.cancel()
            pendingClosureTask = nil
            lastActiveStatus = newState.status
        }
        state = newState
        captureMyResults(from: newState)
        if isHost {
            hostReact(to: newState)
        }
    }

    /// `onDisconnect`は一時的な通信断でも実行されるため、参加者は短い猶予後も
    /// `closed`のままの場合だけ、本当のホスト切断として画面へ反映する。
    private func scheduleClosureConfirmation(_ closedState: RoomState) {
        guard pendingClosureTask == nil else { return }
        pendingClosureTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.hostDisconnectGraceNanoseconds)
            guard !Task.isCancelled, let self, !self.hasLeft else { return }
            self.pendingClosureTask = nil
            self.apply(state: closedState)
        }
    }

    /// ホストのセッションが生きているまま一時切断から復帰した場合は、
    /// onDisconnectを再登録して直前のルーム状態へ戻す。明示退出時はhasLeftで除外する。
    private func recoverHostRoom(to status: RoomState.Status) {
        guard hostRecoveryTask == nil else { return }
        hostRecoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.hostRecoveryTask = nil }
            do {
                let statusRef = self.roomRef.child("status")
                try await statusRef.onDisconnectSetValue(RoomState.Status.closed.rawValue)
                guard !self.hasLeft else { return }
                try await statusRef.setValue(status.rawValue)
            } catch {
                self.lastError = "ルームへの再接続に失敗しました"
                OnlineService.debugLog("ホストのルーム状態復元に失敗: \(error)")
            }
        }
    }

    /// 自分が回答した問題の正誤を記録する
    private func captureMyResults(from state: RoomState) {
        guard let game = state.game,
              game.phase != .question,
              game.reveal != nil,
              state.questions.indices.contains(game.questionIndex) else { return }
        let questionID = state.questions[game.questionIndex].id
        guard let answer = BattleAnswerAcceptance.confirmedAnswers(
            in: game,
            timeLimit: state.settings.timeLimit,
            participantIDs: state.players.map(\.id)
        )
            .first(where: { $0.uid == myID }) else { return }
        myResultsByQuestion[questionID] = answer.choice == state.questions[game.questionIndex].answer
    }

    /// 対戦終了時に一度だけ、正誤履歴・復習リストと戦績へ反映する(要件 §5.4)
    func saveResultsIfNeeded(context: ModelContext) {
        guard !hasSavedResults, state?.status == .finished else { return }
        hasSavedResults = true
        ResultRecorder.record(
            results: myResultsByQuestion.map { ($0.key, $0.value) },
            mode: .battle,
            context: context
        )
        saveBattleRecord(matchType: .friend, context: context)
    }
}
