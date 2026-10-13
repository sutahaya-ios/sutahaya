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
        // スクロールさせず1画面に収める。退出・再戦の操作位置を毎回同じにするため
        BattleResultPodiumView(players: rankedPlayers, myID: session.myID)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(Color(.systemBackground))
        .tint(.blue)
        .navigationTitle("対戦結果")
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

    private var actions: some View {
        VStack(spacing: 10) {
            if session.isHost {
                // 再戦時の広告と処理は従来どおり。参加者はホストの操作で戻る。
                Button {
                    AdsService.shared.presentInterstitialIfDue(for: .battle) {
                        Task { await session.rematch() }
                    }
                } label: {
                    Text(session.isOnline ? "再戦する（ロビーに戻る）" : "もう一度対戦する")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Text("ホストが再戦を選ぶとロビーに戻ります")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
            }
            if !explainedQuestions.isEmpty {
                Button("解説を見る（\(explainedQuestions.count)問）") {
                    isExplanationPresented = true
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            if !session.isOnline, !session.wrongQuestionIDs.isEmpty {
                Button("間違えた\(session.wrongQuestionIDs.count)問を復習") {
                    isReviewPresented = true
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            Button("退出", action: onLeave)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
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

}
