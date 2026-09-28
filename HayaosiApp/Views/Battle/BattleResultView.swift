import SwiftUI
import SwiftData

/// 対戦リザルト:ポイント順の順位表示(同点は同順位)と再戦(要件 §5.1.3・§9-6)
struct BattleResultView: View {
    let session: any BattleSession
    let onLeave: () -> Void

    /// 解説は配信payloadに載っていないので、出題された問題IDから端末内を引く
    @Query private var allQuestions: [Question]

    @State private var isReviewPresented = false
    @State private var isExplanationPresented = false

    var body: some View {
        VStack(spacing: 16) {
            Text("対戦結果")
                .font(.title.bold())

            List {
                ForEach(rankedPlayers) { player in
                    HStack(spacing: 12) {
                        Text("\(rank(of: player))位")
                            .font(.headline)
                            .frame(width: 44, alignment: .leading)
                        Text(player.nickname)
                            .fontWeight(player.id == session.myID ? .bold : .regular)
                        if player.id == session.myID {
                            Text("(自分)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(player.score)pt")
                            .monospacedDigit()
                    }
                    .listRowBackground(
                        player.id == session.myID ? Color.accentColor.opacity(0.1) : nil
                    )
                }
            }
            .listStyle(.insetGrouped)

            VStack(spacing: 12) {
                if session.isHost {
                    Button(session.isOnline ? "再戦する(ロビーに戻る)" : "もう一度対戦する") {
                        Task { await session.rematch() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("ホストが再戦を選ぶとロビーに戻ります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !explainedQuestions.isEmpty {
                    Button("解説を見る(\(explainedQuestions.count)問)") {
                        isExplanationPresented = true
                    }
                    .buttonStyle(.bordered)
                }

                if !session.isOnline, !session.wrongQuestionIDs.isEmpty {
                    Button("間違えた\(session.wrongQuestionIDs.count)問を復習") {
                        isReviewPresented = true
                    }
                    .buttonStyle(.bordered)
                }

                Button("退出") {
                    onLeave()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical)
        .navigationTitle("リザルト")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isExplanationPresented) {
            NavigationStack {
                BattleExplanationListView(
                    questions: explainedQuestions,
                    correctAnswers: correctAnswersByQuestionID
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isExplanationPresented = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isReviewPresented) {
            NavigationStack {
                ReviewListView(questionIDs: session.wrongQuestionIDs)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { isReviewPresented = false }
                        }
                    }
            }
        }
    }

    /// 出題順のまま、解説を持つ問題だけを残す。英単語だけの対戦では空になる
    private var explainedQuestions: [Question] {
        let questionsByID = Dictionary(
            allQuestions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return (session.state?.questions ?? []).compactMap { payload in
            guard let question = questionsByID[payload.id],
                  !question.explanation.isEmpty else { return nil }
            return question
        }
    }

    /// 配信された正解。端末の問題データと版が違っても、対戦で使った答えを見せる
    private var correctAnswersByQuestionID: [String: String] {
        Dictionary(
            (session.state?.questions ?? []).map { ($0.id, $0.answer) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var rankedPlayers: [RoomState.Player] {
        BattleRanking.ranked(session.state?.players ?? [])
    }

    /// 同点は同順位(要件 §5.1.3)。計算はテスト可能な BattleRanking に置く
    private func rank(of player: RoomState.Player) -> Int {
        BattleRanking.rank(of: player, in: rankedPlayers)
    }
}
