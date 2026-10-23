import SwiftUI

struct CompetitiveResultView: View {
    let coordinator: CompetitiveClientCoordinator
    let state: CompetitivePublicState

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(outcomeTitle)
                    .font(.largeTitle.bold())
                rankingCard
                if let settlementResult { rankChangeCard(settlementResult) }
                if let profile = coordinator.profile { statsCard(profile) }
                if !coordinator.canLeaveResult {
                    settlementRecoveryStatus
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if coordinator.canLeaveResult {
                VStack(spacing: 10) {
                    Button {
                        Task { await coordinator.playAgain() }
                    } label: {
                        Text("もう一度対戦")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.isQueueOperationInFlight)

                    Button("ランク戦ホームへ戻る") {
                        coordinator.returnHome()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .navigationTitle("対戦結果")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private var settlementRecoveryStatus: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(
                coordinator.isSettlementRecoveryDelayed
                    ? "更新に時間がかかっています。サーバーの状態を再確認しています…"
                    : "ランクを更新しています…"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if coordinator.isSettlementRecoveryDelayed {
                Button("今すぐ再確認") {
                    coordinator.retrySettlementRecovery()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }

    private var myUID: String? { coordinator.activeSession?.uid }

    private var outcomeTitle: String {
        guard state.finalResult?.outcome == "COMPLETED",
              let myUID,
              let rank = state.finalResult?.ranks[myUID] else {
            return state.finalResult?.outcome == "ABORTED" ? "対戦終了" : "集計中"
        }
        return rank == 1 ? "あなたの勝利！" : "\(rank)位"
    }

    private var rankedParticipants: [CompetitiveParticipant] {
        state.participants.sorted { left, right in
            let leftRank = state.finalResult?.ranks[left.uid] ?? Int.max
            let rightRank = state.finalResult?.ranks[right.uid] ?? Int.max
            return leftRank == rightRank ? left.slot < right.slot : leftRank < rightRank
        }
    }

    private var rankingCard: some View {
        VStack(spacing: 0) {
            ForEach(rankedParticipants) { participant in
                HStack(spacing: 12) {
                    Text(rankText(participant.uid))
                        .font(.headline)
                        .frame(width: 42, alignment: .leading)
                    Image(systemName: participant.kind == .npc ? "cpu" : "person.fill")
                        .foregroundStyle(.secondary)
                    Text(participant.displayName)
                        .lineLimit(1)
                    if participant.uid == myUID {
                        Text("自分")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text("\(score(participant.uid)) pt")
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(participant.uid == myUID ? Color.blue.opacity(0.08) : .clear)
                if participant.id != rankedParticipants.last?.id { Divider() }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var settlementResult: CompetitiveSettlementPlayerResult? {
        guard let myUID else { return nil }
        return state.settlement?.playerResults[myUID]
    }

    private func rankChangeCard(_ result: CompetitiveSettlementPlayerResult) -> some View {
        VStack(spacing: 10) {
            if result.previousTier != result.currentTier {
                Text(tierChangeTitle(result))
                    .font(.headline)
                    .foregroundStyle(
                        tierOrder(result.currentTier) > tierOrder(result.previousTier)
                            ? Color.green
                            : Color.orange
                    )
                Text("\(CompetitiveClientDisplay.tierName(result.previousTier)) → \(CompetitiveClientDisplay.tierName(result.currentTier))")
                    .font(.title3.bold())
            } else {
                Text(CompetitiveClientDisplay.tierName(result.currentTier))
                    .font(.title3.bold())
            }

            if let rating = result.displayRating, let delta = result.ratingDelta {
                HStack(spacing: 8) {
                    Text("Rating \(rating)")
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                }
                .font(.headline)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func statsCard(_ profile: CompetitiveProfileProjection) -> some View {
        HStack {
            resultStat("勝率", CompetitiveClientDisplay.winRateText(profile.stats.winRate))
            resultStat("最高連勝", "\(profile.stats.maxWinStreak)")
            resultStat("累計勝利", "\(profile.stats.totalWins)")
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func resultStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rankText(_ uid: String) -> String {
        guard let rank = state.finalResult?.ranks[uid] else { return "—" }
        return "\(rank)位"
    }

    private func score(_ uid: String) -> Int {
        state.finalResult?.finalScores[uid]
            ?? state.participants.first(where: { $0.uid == uid })?.score
            ?? 0
    }

    private func tierChangeTitle(_ result: CompetitiveSettlementPlayerResult) -> String {
        tierOrder(result.currentTier) > tierOrder(result.previousTier) ? "昇格" : "降格"
    }

    private func tierOrder(_ tier: CompetitiveTier) -> Int {
        switch tier {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .platinum: 3
        case .ratingBattle: 4
        }
    }
}
