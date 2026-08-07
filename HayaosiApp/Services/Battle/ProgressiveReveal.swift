import Foundation

/// 単語を1文字ずつ見せるための計算(要件 §5.1.2)。
/// 問題の開始時刻からの経過時間だけで決まるので、全端末で同じ進み具合になる。
///
/// 早く答えるほど手がかりが少ない、という駆け引きの土台になる部分。
/// 体感の調整は `characterInterval` だけを変えればよい
enum ProgressiveReveal {
    /// 1文字ぶん進むのにかかる時間。**表示ペースの調整はここだけ**。
    /// 短すぎると4択を読む前に単語が出そろってしまい、駆け引きが成立しない
    static let characterInterval: TimeInterval = 0.8
    /// 開始直後に見せる文字数(0文字だと何も判断できないため)
    static let initialCharacters = 1

    /// 経過時間から、いま何文字目まで見えているかを求める
    static func visibleCount(totalCharacters: Int, elapsed: TimeInterval) -> Int {
        guard totalCharacters > initialCharacters else { return max(0, totalCharacters) }
        guard characterInterval > 0, elapsed.isFinite else { return totalCharacters }

        let advanced = Int(max(0, elapsed) / characterInterval)
        return min(totalCharacters, initialCharacters + advanced)
    }

    /// 指定の文字数が表示されるまでにかかる時間。ボットが「何文字目で答えるか」を決めるのに使う
    static func time(forVisibleCount count: Int) -> TimeInterval {
        let steps = max(0, count - initialCharacters)
        return Double(steps) * characterInterval
    }

    /// 単語全体が出そろうまでの時間
    static func fullRevealDuration(totalCharacters: Int) -> TimeInterval {
        time(forVisibleCount: totalCharacters)
    }
}
