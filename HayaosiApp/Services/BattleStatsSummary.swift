import Foundation

/// プロフィールに出す戦績。対戦数と1位回数から1位率を導く
struct ProfileBattleStats: Equatable {
    let battleCount: Int
    let firstPlaceCount: Int

    var firstPlaceRate: Double {
        guard battleCount > 0 else { return 0 }
        return Double(firstPlaceCount) / Double(battleCount)
    }

    /// 1試合もしていないときの「0.0%」は誤解を招くのでダッシュにする
    var firstPlaceRateText: String {
        guard battleCount > 0 else { return "—" }
        return firstPlaceRate.formatted(.percent.precision(.fractionLength(1)))
    }
}

/// 対戦記録の集計。Viewに埋めるとテストできないので純粋な計算として切り出している
enum BattleStatsSummary {
    /// `matchType` が nil なら全区分の合計
    static func calculate(
        records: [BattleRecord],
        matchType: BattleMatchType? = nil
    ) -> ProfileBattleStats {
        let targets = matchType.map { type in
            records.filter { $0.matchType == type }
        } ?? records

        return ProfileBattleStats(
            battleCount: targets.count,
            firstPlaceCount: targets.filter { $0.rank == 1 }.count
        )
    }
}
