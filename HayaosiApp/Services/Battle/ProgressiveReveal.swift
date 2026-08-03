import Foundation

/// 文字送り型(要件 §5.1.2 案B)で「いまどこまで問題文を見せるか」の計算。
/// 問題の開始時刻からの経過時間だけで決まるので、全端末で同じ進み具合になる
enum ProgressiveReveal {
    /// 全文が出そろうまでに制限時間のこの割合を使う。残りは「全文を見て考える時間」
    static let revealRatio = 0.6
    /// 開始直後に見せる文字数(0文字だと何も判断できないため)
    static let initialCharacters = 1

    static func visibleCount(totalCharacters: Int, elapsed: TimeInterval, timeLimit: TimeInterval) -> Int {
        guard totalCharacters > initialCharacters else { return max(0, totalCharacters) }
        guard timeLimit > 0, elapsed.isFinite else { return totalCharacters }

        let revealDuration = timeLimit * revealRatio
        guard elapsed < revealDuration else { return totalCharacters }

        let progress = max(0, elapsed) / revealDuration
        let revealed = Double(totalCharacters - initialCharacters) * progress
        return min(totalCharacters, initialCharacters + Int(revealed))
    }
}
