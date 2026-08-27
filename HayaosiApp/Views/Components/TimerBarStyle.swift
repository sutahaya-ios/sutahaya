import SwiftUI

/// 制限時間バーで共通利用する見た目
enum TimerBarStyle {
    static let normalTint: Color = .mint
    static let urgentTint: Color = .red

    /// 残り時間が少ないと見なす秒数の上限
    private static let urgentSeconds: TimeInterval = 5
    /// 制限時間に対する割合の上限
    private static let urgentRatio: Double = 0.3

    /// 警告色へ切り替える残り時間。
    /// 秒数だけで決めると、制限時間5秒の練習では最初から警告色になってしまうため、
    /// 制限時間が短いときは割合のほうを使う
    static func urgentThreshold(for timeLimit: TimeInterval) -> TimeInterval {
        min(urgentSeconds, timeLimit * urgentRatio)
    }
}
