import Foundation

/// リザルトの順位計算(要件 §5.1.3:ポイント順・同点は同順位)。
/// Viewに埋めるとテストできないので純粋な計算として切り出している
enum BattleRanking {
    /// スコアの高い順に並べる
    static func ranked(_ players: [RoomState.Player]) -> [RoomState.Player] {
        players.sorted { $0.score > $1.score }
    }

    /// 同点は同順位(自分より高得点の人数+1。例:3,3,1 → 1位,1位,3位)
    static func rank(of player: RoomState.Player, in players: [RoomState.Player]) -> Int {
        players.filter { $0.score > player.score }.count + 1
    }
}
