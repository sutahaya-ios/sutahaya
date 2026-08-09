import Foundation

/// CPUの強さプロファイル。値はここが唯一の出典
struct CPUProfile {
    let id: String
    let nickname: String
    /// 問題ごとに回答に参加する確率
    let answerProbability: Double
    /// 回答が正解になる確率
    let correctProbability: Double
    /// 文字送り型で、単語が何割まで表示されたら答えるか。強いCPUほど少ない文字数で答える
    let answerRevealFraction: ClosedRange<Double>
    /// 選択肢を読んで選ぶまでの間。これが無いと人間が4択を読む前に決着してしまう
    let thinkingDelay: ClosedRange<Double>

    /// 先頭から参加人数ぶんを使う(1体なら「中」だけ)
    static let roster = [
        CPUProfile(id: "cpu-normal", nickname: "CPU(中)", answerProbability: 0.9, correctProbability: 0.55,
                   answerRevealFraction: 0.55...0.85, thinkingDelay: 1.5...3.0),
        CPUProfile(id: "cpu-strong", nickname: "CPU(強)", answerProbability: 0.95, correctProbability: 0.75,
                   answerRevealFraction: 0.35...0.65, thinkingDelay: 0.8...1.8),
        CPUProfile(id: "cpu-weak", nickname: "CPU(弱)", answerProbability: 0.7, correctProbability: 0.35,
                   answerRevealFraction: 0.8...1.0, thinkingDelay: 2.5...4.5),
        CPUProfile(id: "cpu-a", nickname: "CPU(A)", answerProbability: 0.8, correctProbability: 0.45,
                   answerRevealFraction: 0.65...0.95, thinkingDelay: 1.8...3.5),
        CPUProfile(id: "cpu-b", nickname: "CPU(B)", answerProbability: 0.85, correctProbability: 0.5,
                   answerRevealFraction: 0.5...0.8, thinkingDelay: 1.3...2.8),
        CPUProfile(id: "cpu-c", nickname: "CPU(C)", answerProbability: 0.75, correctProbability: 0.4,
                   answerRevealFraction: 0.7...1.0, thinkingDelay: 2.0...4.0),
        CPUProfile(id: "cpu-d", nickname: "CPU(D)", answerProbability: 0.9, correctProbability: 0.6,
                   answerRevealFraction: 0.45...0.75, thinkingDelay: 1.0...2.2)
    ]
}

/// CPUの回答判断(参加するか・いつ・どれを選ぶか)。
/// セッションの状態を持たない純粋な計算に分離してあり、`random` を差し替えると
/// テストで判断を固定できる(既定は本物の乱数で、本番の挙動は従来と同じ)
struct CPUAnswerStrategy {
    /// 文字送り型での1回の回答計画
    struct ProgressivePlan {
        let delay: TimeInterval
        let choice: String
        /// 答えると決めた時点の表示文字数(回答記録に使う)
        let visibleCount: Int
    }

    /// 制限時間ぎりぎりの回答は不自然なので、CPUは制限時間のこの割合までに動く
    static let deadlineRatio = 0.8
    /// 判断に使う乱数。テストでは固定値を返す実装に差し替える
    var random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }

    /// この問題に参加する(答えようとする)か
    func participates(_ cpu: CPUProfile) -> Bool {
        random(0...1) < cpu.answerProbability
    }

    /// 正答率に従って選択肢を決める
    func choice(for cpu: CPUProfile, in question: RoomState.QuestionPayload) -> String {
        guard random(0...1) >= cpu.correctProbability else { return question.answer }
        let wrongs = question.choices.filter { $0 != question.answer }
        guard !wrongs.isEmpty else { return question.answer }
        let index = min(wrongs.count - 1, Int(random(0...1) * Double(wrongs.count)))
        return wrongs[index]
    }

    /// 文字送り型:目標の表示文字数から回答時刻を逆算し、考える間を足す
    func progressivePlan(for cpu: CPUProfile,
                         question: RoomState.QuestionPayload,
                         timeLimit: TimeInterval) -> ProgressivePlan {
        let total = question.text.count
        let fraction = random(cpu.answerRevealFraction)
        let target = max(1, min(total, Int((Double(total) * fraction).rounded(.up))))
        let delay = min(ProgressiveReveal.time(forVisibleCount: target) + random(cpu.thinkingDelay),
                        timeLimit * Self.deadlineRatio)
        return ProgressivePlan(delay: delay, choice: choice(for: cpu, in: question), visibleCount: target)
    }

}
