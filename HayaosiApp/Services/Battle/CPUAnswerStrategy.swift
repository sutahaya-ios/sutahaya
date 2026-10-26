import Foundation

/// Friend Battle / Bot Battle / Online Rankedで共有する7段階のNPC強度。
/// 表示名ではなく内部profile名として扱う。
enum NPCStrength: String, CaseIterable {
    case veryWeak = "超弱"
    case weak = "弱"
    case slightlyWeak = "ちょい弱"
    case normal = "普通"
    case slightlyStrong = "ちょい強"
    case strong = "強"
    case veryStrong = "鬼強"

    var remainingTimeRatio: Double {
        switch self {
        case .veryWeak: 0.15
        case .weak: 0.25
        case .slightlyWeak: 0.35
        case .normal: 0.50
        case .slightlyStrong: 0.55
        case .strong: 0.60
        case .veryStrong: 0.70
        }
    }

    var unansweredDenominator: Double {
        switch self {
        case .veryWeak: 3
        case .weak: 5
        case .slightlyWeak: 8
        case .normal: 15
        case .slightlyStrong: 20
        case .strong: 25
        case .veryStrong: 30
        }
    }
}

/// CPUの強さプロファイル。値はここが唯一の出典
struct CPUProfile: Identifiable {
    let id: String
    let nickname: String
    let strength: NPCStrength
    /// 回答が正解になる確率
    let correctProbability: Double

    /// 問題ごとに回答に参加する確率。無回答率はstrengthの指定値から導出する。
    var answerProbability: Double {
        1 - 1 / strength.unansweredDenominator
    }

    var strengthDescription: String {
        "正答率の目安 \(Int((correctProbability * 100).rounded()))%"
    }

    /// 先頭から参加人数ぶんを使う(1体なら「中」だけ)
    static let roster = [
        CPUProfile(id: "cpu-normal", nickname: "CPU(中)", strength: .slightlyStrong,
                   correctProbability: 0.55),
        CPUProfile(id: "cpu-strong", nickname: "CPU(強)", strength: .veryStrong,
                   correctProbability: 0.75),
        CPUProfile(id: "cpu-weak", nickname: "CPU(弱)", strength: .veryWeak,
                   correctProbability: 0.35),
        CPUProfile(id: "cpu-a", nickname: "CPU(A)", strength: .slightlyWeak,
                   correctProbability: 0.45),
        CPUProfile(id: "cpu-b", nickname: "CPU(B)", strength: .normal,
                   correctProbability: 0.50),
        CPUProfile(id: "cpu-c", nickname: "CPU(C)", strength: .weak,
                   correctProbability: 0.40),
        CPUProfile(id: "cpu-d", nickname: "CPU(D)", strength: .strong,
                   correctProbability: 0.60)
    ]

    static var strengthOrderedRoster: [CPUProfile] {
        roster.sorted { $0.correctProbability < $1.correctProbability }
    }
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

    static let minimumAnswerDelay: TimeInterval = 1.2
    static let deadlineSafetyMargin: TimeInterval = 0.1
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

    /// 強度ごとの平均残り時間を中心に、中央が出やすい三角分布で回答時刻を揺らす。
    func progressivePlan(for cpu: CPUProfile,
                         question: RoomState.QuestionPayload,
                         timeLimit: TimeInterval) -> ProgressivePlan {
        let latest = max(Self.minimumAnswerDelay, timeLimit - Self.deadlineSafetyMargin)
        let target = min(
            latest,
            max(Self.minimumAnswerDelay, timeLimit * (1 - cpu.strength.remainingTimeRatio))
        )
        let jitterLimit = max(
            0,
            min(target - Self.minimumAnswerDelay, latest - target)
        )
        let triangular = random(0...1) + random(0...1) - 1
        let delay = min(latest, max(Self.minimumAnswerDelay, target + triangular * jitterLimit))
        let visibleCount = ProgressiveReveal.visibleCount(
            totalCharacters: question.text.count,
            elapsed: delay
        )
        return ProgressivePlan(
            delay: delay,
            choice: choice(for: cpu, in: question),
            visibleCount: visibleCount
        )
    }

}
