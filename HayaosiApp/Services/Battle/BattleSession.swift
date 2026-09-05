import Foundation
import Observation
import SwiftData

enum BattleAnswerSubmissionOutcome: Equatable {
    /// CPU対戦など、呼び出し内で結果まで確定した。
    case accepted
    /// RTDBへの送信は拒否されておらず、hostの採点結果を待っている。
    case awaitingHostResult
    /// 期限外、回答権なし、通信エラーなどにより正式に受理されなかった。
    case rejected
}

/// 対戦セッションの共通インターフェース。
/// オンライン対戦(OnlineBattleSession=Firebase)とCPU対戦(CPUBattleSession=ローカル)が実装し、
/// ロビー・対戦・リザルト画面はこのプロトコル越しに描画する
@MainActor
protocol BattleSession: AnyObject, Observable {
    var myID: String { get }
    var isHost: Bool { get }
    /// オンライン対戦か(false=CPU対戦。参加コードや招待UIを出さない)
    var isOnline: Bool { get }
    /// Firebaseのサーバー時刻 - 端末時刻(ms)。CPU対戦は0。
    var battleClockOffsetMS: Double { get }
    /// ホストが開始操作済みで、Firebaseへ開始状態を書き込んでいる途中か。
    var isStartingMatch: Bool { get }
    var state: RoomState? { get }
    /// この対戦で自分が間違えた問題。リザルトから既存の復習機能へ渡す
    var wrongQuestionIDs: Set<String> { get }

    func startGame(questions: [Question]) async
    func rematch() async
    /// 待機中の同じルームを維持したまま、対戦設定だけを更新する。
    func updateSettings(_ settings: RoomState.Settings) async throws
    /// 回答する。選択肢を押した瞬間が回答にあたるため、
    /// そのとき何文字まで見えていたかを一緒に渡す(記録と、後からの調整に使う)
    func submitAnswer(_ choice: String, visibleCount: Int)
    /// 通信結果まで必要な画面向け。送信中とhost確定待ちを正式拒否から分離して返す。
    func submitAnswer(
        _ choice: String,
        visibleCount: Int,
        completion: @escaping (BattleAnswerSubmissionOutcome) -> Void
    )
    func leave()
    func saveResultsIfNeeded(context: ModelContext)
}

extension BattleSession {
    var battleClockOffsetMS: Double { 0 }
    var isStartingMatch: Bool { false }

    /// 自分の順位を戦績として残す。二重保存を防ぐため `saveResultsIfNeeded` のガードの内側から呼ぶ
    func saveBattleRecord(matchType: BattleMatchType, context: ModelContext) {
        guard let players = state?.players,
              let me = players.first(where: { $0.id == myID }) else { return }

        ResultRecorder.recordBattle(
            matchType: matchType,
            rank: BattleRanking.rank(of: me, in: players),
            participantCount: players.count,
            score: me.score,
            context: context
        )
    }

    /// CPU対戦など同期的に回答できる実装は、従来の回答処理を呼んだ時点で成功とみなす。
    func submitAnswer(
        _ choice: String,
        visibleCount: Int,
        completion: @escaping (BattleAnswerSubmissionOutcome) -> Void
    ) {
        submitAnswer(choice, visibleCount: visibleCount)
        completion(.accepted)
    }

    var currentQuestion: RoomState.QuestionPayload? {
        guard let state, let game = state.game,
              state.questions.indices.contains(game.questionIndex) else { return nil }
        return state.questions[game.questionIndex]
    }

    func player(for uid: String?) -> RoomState.Player? {
        guard let uid else { return nil }
        return state?.players.first { $0.id == uid }
    }

    /// いま何文字目まで見えているか。出題中だけ経過時間に応じて増える
    func visibleCharacterCount(at date: Date) -> Int {
        guard let state, let question = currentQuestion else { return 0 }
        guard let game = state.game, game.phase == .question else { return question.text.count }

        let elapsed = (battleTimeMS(at: date) - game.effectiveStartedAtMS) / 1_000
        return ProgressiveReveal.visibleCount(totalCharacters: question.text.count, elapsed: elapsed)
    }

    /// 自分がこの問題にまだ回答できるか(未回答かつ誤答していない)
    var canAnswerNow: Bool {
        canAnswer(at: .now)
    }

    func canAnswer(at date: Date) -> Bool {
        guard let game = state?.game, game.phase == .question else { return false }
        let nowMS = battleTimeMS(at: date)
        let deadlineMS = game.effectiveStartedAtMS + (state?.settings.timeLimit ?? 0) * 1_000
        guard nowMS >= game.effectiveStartedAtMS, nowMS <= deadlineMS else { return false }
        guard !game.failedIDs.contains(myID) else { return false }
        return !game.answers.contains { $0.uid == myID }
    }

    /// 表示用の残り時間(開始タイムスタンプ基準の近似値)
    func remainingTime(at date: Date) -> TimeInterval {
        guard let state, let game = state.game, game.phase == .question else { return 0 }
        let elapsed = max(0, (battleTimeMS(at: date) - game.effectiveStartedAtMS) / 1_000)
        return max(0, state.settings.timeLimit - elapsed)
    }

    /// 端末のDateを、対戦で共有するFirebaseサーバー時刻(ms)へ変換する。
    func battleTimeMS(at date: Date) -> Double {
        date.timeIntervalSince1970 * 1_000 + battleClockOffsetMS
    }

    /// Firebaseサーバー時刻(ms)を、この端末のDateと比較できる値へ変換する。
    func localTimeMS(forBattleTimeMS timeMS: Double) -> Double {
        timeMS - battleClockOffsetMS
    }
}
