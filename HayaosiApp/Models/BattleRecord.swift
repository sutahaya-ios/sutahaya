import Foundation
import SwiftData

/// 対戦の区分。ランダムマッチはマッチング機能が未実装のため、書き込む経路はまだない
enum BattleMatchType: String, Codable, CaseIterable, Identifiable {
    case friend
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .friend: return "フレンド戦"
        case .random: return "ランダムマッチ"
        }
    }
}

/// 1試合ぶんの戦績。問題ごとの正誤は `AnswerRecord` が持つので、ここは順位だけを残す
@Model
final class BattleRecord {
    var playedAt: Date
    var matchTypeRaw: String
    var rank: Int
    var participantCount: Int
    var score: Int

    init(
        matchType: BattleMatchType,
        rank: Int,
        participantCount: Int,
        score: Int,
        playedAt: Date = .now
    ) {
        self.matchTypeRaw = matchType.rawValue
        self.rank = rank
        self.participantCount = participantCount
        self.score = score
        self.playedAt = playedAt
    }

    var matchType: BattleMatchType { BattleMatchType(rawValue: matchTypeRaw) ?? .friend }
}
