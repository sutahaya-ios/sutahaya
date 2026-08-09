import Foundation
import Observation
import SwiftData

/// 対戦セッションの共通インターフェース。
/// オンライン対戦(OnlineBattleSession=Firebase)とCPU対戦(CPUBattleSession=ローカル)が実装し、
/// ロビー・対戦・リザルト画面はこのプロトコル越しに描画する
@MainActor
protocol BattleSession: AnyObject, Observable {
    var myID: String { get }
    var isHost: Bool { get }
    /// オンライン対戦か(false=CPU対戦。参加コードや招待UIを出さない)
    var isOnline: Bool { get }
    var state: RoomState? { get }

    func startGame(questions: [Question]) async
    func rematch() async
    /// 回答する。選択肢を押した瞬間が回答にあたるため、
    /// そのとき何文字まで見えていたかを一緒に渡す(記録と、後からの調整に使う)
    func submitAnswer(_ choice: String, visibleCount: Int)
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

    /// いま何文字目まで見えているか。出題中だけ経過時間に応じて増える
    func visibleCharacterCount(at date: Date) -> Int {
        guard let state, let question = currentQuestion else { return 0 }
        guard let game = state.game, game.phase == .question else { return question.text.count }

        let elapsed = date.timeIntervalSince1970 - game.effectiveStartedAtMS / 1_000
        return ProgressiveReveal.visibleCount(totalCharacters: question.text.count, elapsed: elapsed)
    }

    /// 自分がこの問題にまだ回答できるか(未回答かつ誤答していない)
    var canAnswerNow: Bool {
        guard let game = state?.game, game.phase == .question else { return false }
        let nowMS = Date().timeIntervalSince1970 * 1_000
        let deadlineMS = game.effectiveStartedAtMS + (state?.settings.timeLimit ?? 0) * 1_000
        guard nowMS >= game.effectiveStartedAtMS, nowMS <= deadlineMS else { return false }
        guard !game.failedIDs.contains(myID) else { return false }
        return !game.answers.contains { $0.uid == myID }
    }

    /// 表示用の残り時間(開始タイムスタンプ基準の近似値)
    func remainingTime(at date: Date) -> TimeInterval {
        guard let state, let game = state.game, game.phase == .question else { return 0 }
        let elapsed = max(0, date.timeIntervalSince1970 - game.effectiveStartedAtMS / 1_000)
        return max(0, state.settings.timeLimit - elapsed)
    }
}
