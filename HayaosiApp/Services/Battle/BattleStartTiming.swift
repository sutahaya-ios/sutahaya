import Foundation

/// 対戦開始画面の表示時間を、配信された開始時刻と端末での受信時刻から求める
enum BattleStartTiming {
    static func remainingDisplayTime(
        scheduledStartAtMS: Double,
        observedAt: Date,
        now: Date
    ) -> TimeInterval {
        max(0, displayEndDate(scheduledStartAtMS: scheduledStartAtMS, observedAt: observedAt)
            .timeIntervalSince(now))
    }

    static func progress(
        scheduledStartAtMS: Double,
        observedAt: Date,
        now: Date
    ) -> Double {
        let endDate = displayEndDate(scheduledStartAtMS: scheduledStartAtMS, observedAt: observedAt)
        let duration = max(BattleRules.minimumMatchStartDisplay, endDate.timeIntervalSince(observedAt))
        let elapsed = max(0, now.timeIntervalSince(observedAt))
        return min(1, elapsed / duration)
    }

    private static func displayEndDate(scheduledStartAtMS: Double, observedAt: Date) -> Date {
        let scheduledStart = Date(timeIntervalSince1970: scheduledStartAtMS / 1_000)
        let minimumEnd = observedAt.addingTimeInterval(BattleRules.minimumMatchStartDisplay)
        return max(scheduledStart, minimumEnd)
    }
}
