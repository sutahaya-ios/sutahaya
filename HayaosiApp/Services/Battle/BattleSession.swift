import Foundation
import Observation
import SwiftData

/// 対戦セッションの共通インターフェース。
/// オンライン対戦(OnlineBattleSession=Firebase)とボット対戦(BotBattleSession=ローカル)が実装し、
/// ロビー・対戦・リザルト画面はこのプロトコル越しに描画する
@MainActor
protocol BattleSession: AnyObject, Observable {
    var myID: String { get }
    var isHost: Bool { get }
    /// オンライン対戦か(false=ボット対戦。参加コードや招待UIを出さない)
    var isOnline: Bool { get }
    var state: RoomState? { get }

    func startGame(questions: [Question]) async
    func rematch() async
    func buzz()
    func submitAnswer(_ choice: String)
    func leave()
    func saveResultsIfNeeded(context: ModelContext)
}

extension BattleSession {
    var currentQuestion: RoomState.QuestionPayload? {
        guard let state, let game = state.game,
              state.questions.indices.contains(game.questionIndex) else { return nil }
        return state.questions[game.questionIndex]
    }

    func player(for uid: String?) -> RoomState.Player? {
        guard let uid else { return nil }
        return state?.players.first { $0.id == uid }
    }

    /// 表示用の残り時間(開始タイムスタンプ基準の近似値)
    func remainingTime(at date: Date) -> TimeInterval {
        guard let state, let game = state.game, game.phase == .question else { return 0 }
        let elapsed = date.timeIntervalSince1970 - game.startedAtMS / 1000
        return max(0, state.settings.timeLimit - elapsed)
    }
}
