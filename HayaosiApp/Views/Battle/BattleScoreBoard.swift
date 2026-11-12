import SwiftUI

/// 対戦中の参加者を、回答順と正誤が分かる丸アイコン列で表示する
struct BattleScoreBoard: View {
    private static let iconSize: CGFloat = 50
    private static let playerWidth: CGFloat = 58
    private static let playerSpacing: CGFloat = 10
    private static let playerColors: [Color] = [
        Color(red: 0.18, green: 0.49, blue: 0.87),
        Color(red: 0.37, green: 0.28, blue: 0.78),
        Color(red: 0.62, green: 0.32, blue: 0.76),
        Color(red: 0.91, green: 0.48, blue: 0.16),
        Color(red: 0.00, green: 0.55, blue: 0.72),
        Color(red: 0.79, green: 0.48, blue: 0.08),
        Color(red: 0.25, green: 0.40, blue: 0.74),
        Color(red: 0.42, green: 0.36, blue: 0.65)
    ]

    private let displayPlayers: [DisplayPlayer]
    let usesCorrectCount: Bool

    init(
        players: [RoomState.Player],
        hostID: String,
        answers: [RoomState.Answer],
        failedIDs: Set<String>,
        correctIDs: Set<String>,
        usesCorrectCount: Bool = false
    ) {
        displayPlayers = Self.entries(
            players: players,
            hostID: hostID,
            answers: answers,
            failedIDs: failedIDs,
            correctIDs: correctIDs
        ).map { entry in
            DisplayPlayer(
                id: entry.player.id,
                nickname: entry.player.nickname,
                score: entry.player.score,
                badge: entry.answerRank.map(DisplayBadge.answerRank),
                answerState: entry.result.map {
                    switch $0 {
                    case .correct: .correct
                    case .wrong: .wrong
                    }
                }
            )
        }
        self.usesCorrectCount = usesCorrectCount
    }

    /// Server projectionを表示するオンライン対戦向け。通常対戦と同じPlayer列だけを再利用する。
    init(displayPlayers: [DisplayPlayer], usesCorrectCount: Bool = false) {
        self.displayPlayers = displayPlayers
        self.usesCorrectCount = usesCorrectCount
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Self.playerSpacing) {
                ForEach(displayPlayers) { player in
                    playerIcon(player)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
        .frame(height: 90)
        .animation(BattleAnimation.playerOrder, value: displayPlayers.map(\.id))
    }

    private func playerIcon(_ player: DisplayPlayer) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(playerColor(for: player.id))
                    .frame(width: Self.iconSize, height: Self.iconSize)

                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.white)

                if !usesCorrectCount, let badge = player.badge {
                    badgeView(badge)
                        .offset(x: -18, y: -18)
                }

                if let answerState = player.answerState {
                    answerStateMark(answerState)
                        .offset(x: 18, y: 18)
                }
            }
            .frame(width: Self.iconSize, height: Self.iconSize)

            Text(player.nickname)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: Self.playerWidth)

            Text(usesCorrectCount ? "\(player.score)問正解" : "\(player.score)pt")
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .frame(width: Self.playerWidth)
    }

    @ViewBuilder
    private func badgeView(_ badge: DisplayBadge) -> some View {
        Text(badge.text)
            .font(.caption2.bold())
            .foregroundStyle(badge.foregroundStyle)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.systemGray4)))
    }

    @ViewBuilder
    private func answerStateMark(_ state: DisplayAnswerState) -> some View {
        switch state {
        case .answered:
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.orange, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        case .correct, .wrong:
            Text(state == .correct ? "○" : "×")
                .font(.title3.bold())
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.92), in: Circle())
        }
    }

    private func playerColor(for playerID: String) -> Color {
        let colorIndex = playerID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.playerColors.count
        return Self.playerColors[colorIndex]
    }

    /// 基本順(ホスト→入室順)を土台に、回答済みプレイヤーだけを回答時刻順で前へ出す
    static func entries(
        players: [RoomState.Player],
        hostID: String,
        answers: [RoomState.Answer],
        failedIDs: Set<String>,
        correctIDs: Set<String>
    ) -> [Entry] {
        let basePlayers = players.sorted { left, right in
            if left.id == hostID { return true }
            if right.id == hostID { return false }
            if left.joinedAtMS == right.joinedAtMS { return left.id < right.id }
            return left.joinedAtMS < right.joinedAtMS
        }
        let baseIndex = Dictionary(uniqueKeysWithValues: basePlayers.enumerated().map { ($0.element.id, $0.offset) })
        let playerIDs = Set(basePlayers.map(\.id))
        let orderedAnswers = answers
            .filter { playerIDs.contains($0.uid) }
            .sorted { left, right in
                if left.answeredAtMS == right.answeredAtMS {
                    return (baseIndex[left.uid] ?? 0) < (baseIndex[right.uid] ?? 0)
                }
                return left.answeredAtMS < right.answeredAtMS
            }

        var answerRanks: [String: Int] = [:]
        for answer in orderedAnswers where answerRanks[answer.uid] == nil {
            answerRanks[answer.uid] = answerRanks.count + 1
        }

        let orderedPlayers = basePlayers.sorted { left, right in
            let leftRank = answerRanks[left.id]
            let rightRank = answerRanks[right.id]
            switch (leftRank, rightRank) {
            case let (.some(leftRank), .some(rightRank)):
                return leftRank < rightRank
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return (baseIndex[left.id] ?? 0) < (baseIndex[right.id] ?? 0)
            }
        }

        return orderedPlayers.map { player in
            Entry(
                player: player,
                answerRank: answerRanks[player.id],
                result: answerResult(for: player.id, failedIDs: failedIDs, correctIDs: correctIDs)
            )
        }
    }

    private static func answerResult(
        for playerID: String,
        failedIDs: Set<String>,
        correctIDs: Set<String>
    ) -> AnswerResult? {
        if correctIDs.contains(playerID) { return .correct }
        if failedIDs.contains(playerID) { return .wrong }
        return nil
    }
}

extension BattleScoreBoard {
    struct DisplayPlayer: Identifiable, Equatable {
        let id: String
        let nickname: String
        let score: Int
        let badge: DisplayBadge?
        let answerState: DisplayAnswerState?
    }

    enum DisplayBadge: Equatable {
        case answerRank(Int)
        case scoreDelta(Int)

        var text: String {
            switch self {
            case let .answerRank(rank):
                switch rank {
                case 1: return "1st"
                case 2: return "2nd"
                case 3: return "3rd"
                default: return "\(rank)th"
                }
            case let .scoreDelta(delta):
                if delta > 0 { return "+\(delta)" }
                if delta == 0 { return "±0" }
                return "\(delta)"
            }
        }

        var foregroundStyle: Color {
            switch self {
            case .answerRank: return .primary
            case let .scoreDelta(delta) where delta > 0: return .green
            case let .scoreDelta(delta) where delta < 0: return .red
            case .scoreDelta: return .secondary
            }
        }
    }

    enum DisplayAnswerState: Equatable {
        case answered
        case correct
        case wrong
    }

    struct Entry: Identifiable, Equatable {
        let player: RoomState.Player
        let answerRank: Int?
        let result: AnswerResult?

        var id: String { player.id }
    }

    enum AnswerResult: Equatable {
        case correct
        case wrong

        var symbol: String {
            switch self {
            case .correct: return "○"
            case .wrong: return "×"
            }
        }
    }
}

#Preview("回答順と正誤") {
    BattleScoreBoard(
        players: [
            .init(id: "host", nickname: "たける", score: 1, joinedAtMS: 0),
            .init(id: "cpu-normal", nickname: "CPU(中)", score: -1, joinedAtMS: 1),
            .init(id: "cpu-strong", nickname: "CPU(強)", score: 1, joinedAtMS: 2)
        ],
        hostID: "host",
        answers: [
            .init(uid: "cpu-normal", questionIndex: 0, choice: "誤答", answeredAtMS: 100, visibleCount: 3),
            .init(uid: "host", questionIndex: 0, choice: "正答", answeredAtMS: 200, visibleCount: 4)
        ],
        failedIDs: ["cpu-normal"],
        correctIDs: ["host"]
    )
    .padding()
}
