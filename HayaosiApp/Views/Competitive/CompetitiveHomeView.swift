import SwiftUI

struct CompetitiveHomeView: View {
    let profile: CompetitiveProfileProjection?
    let isLoading: Bool
    let cooldownEndsAtEpochMS: Double?
    let serverTimeOffsetMS: Double
    let badgeEvolutionRequest: CompetitiveBadgeEvolutionRequest?
    let tierChangeAnimationRequest: CompetitiveTierChangeAnimationRequest?
    let onBadgeEvolutionHandled: (UUID) -> Void
    let onTierChangeAnimationHandled: (UUID) -> Void
    let onStart: () -> Void

    @State private var badgeStageOverride: CompetitiveClientDisplay.RankBadgeStage?
    @State private var badgeRotation = 0.0
    @State private var badgeScale = 1.0
    @State private var badgeOpacity = 1.0
    @State private var badgeGlowOpacity = 0.0
    @State private var tierChangeLabel: String?
    @State private var tierChangeLabelOpacity = 0.0

    private let backgroundColor = Color(red: 0.965, green: 0.972, blue: 0.99)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                rankOverview
                statsCards
                rulesCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(backgroundColor)
        }
        .navigationTitle("ランク戦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(backgroundColor.ignoresSafeArea())
        .task(id: badgeEvolutionRequest?.id) {
            await playBadgeEvolutionIfNeeded()
        }
        .task(id: tierChangeAnimationRequest?.id) {
            await playTierChangeAnimationIfNeeded()
        }
        .onChange(of: profile) { _, _ in
            guard badgeEvolutionRequest == nil,
                  tierChangeAnimationRequest == nil else { return }
            badgeStageOverride = nil
        }
    }

    private var rankOverview: some View {
        VStack(spacing: 14) {
            rankIdentity

            if let profile {
                ratingPill(profile)
                if let progress = CompetitiveClientDisplay.rankProgress(for: profile) {
                    rankProgress(profile: profile, progress: progress)
                }
            } else {
                Text("初回の対戦参加後にServerから取得します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rankIdentity: some View {
        VStack(spacing: 2) {
            if let profile {
                Image(rankBadgeAssetName(for: profile))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 270, height: 190)
                    .rotation3DEffect(
                        .degrees(badgeRotation),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    .scaleEffect(badgeScale)
                    .opacity(badgeOpacity)
                    .shadow(
                        color: tierAccentColor(profile.currentTier).opacity(badgeGlowOpacity),
                        radius: 24
                    )
                    .overlay(alignment: .bottom) {
                        if let tierChangeLabel {
                            Text(tierChangeLabel)
                                .font(.headline.bold())
                                .foregroundStyle(
                                    tierChangeAnimationRequest?.direction == .promotion
                                        ? Color.green
                                        : Color.secondary
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                                .opacity(tierChangeLabelOpacity)
                                .offset(y: 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(
                        "\(CompetitiveClientDisplay.tierName(profile.currentTier))ランクバッジ"
                    )

                Text(CompetitiveClientDisplay.tierName(profile.currentTier))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(tierAccentColor(profile.currentTier))
            } else {
                ProgressView()
                    .frame(width: 270, height: 190)
                Text("ランク情報を準備中")
                    .font(.title2.bold())
            }
        }
    }

    private func ratingPill(_ profile: CompetitiveProfileProjection) -> some View {
        HStack(spacing: 10) {
            Text("Rating")
                .foregroundStyle(Color(red: 0.38, green: 0.48, blue: 0.66))
            if let rating = CompetitiveClientDisplay.ratingValue(for: profile) {
                Text("\(rating)")
                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.36))
                    .monospacedDigit()
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3.weight(.bold))
        .padding(.horizontal, 24)
        .frame(minHeight: 44)
        .background(Color.blue.opacity(0.065), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func rankProgress(
        profile: CompetitiveProfileProjection,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let remaining = profile.pointsToNextTier {
                HStack(spacing: 8) {
                    Text("次のランクまで")
                        .foregroundStyle(Color(red: 0.30, green: 0.36, blue: 0.48))
                    Text("あと \(max(0, remaining)) pt")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
                .font(.headline)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.82, green: 0.84, blue: 0.90))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.08, green: 0.47, blue: 0.96), .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)

                    Path { path in
                        let markerX = geometry.size.width / 2
                        path.move(to: CGPoint(x: markerX, y: -3))
                        path.addLine(to: CGPoint(x: markerX, y: geometry.size.height + 3))
                    }
                    .stroke(
                        Color.gray.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                }
            }
            .frame(height: 12)
            .accessibilityLabel("次のランクまでの進捗")
            .accessibilityValue("\(Int((progress * 100).rounded()))パーセント")
        }
        .frame(maxWidth: .infinity)
    }

    private var statsCards: some View {
        HStack(spacing: 10) {
            statCard(
                title: "勝率",
                value: profile.map { CompetitiveClientDisplay.winRateText($0.stats.winRate) } ?? "—",
                systemImage: "trophy.fill",
                color: .blue
            )
            statCard(
                title: "最高連勝",
                value: profile.map { "\($0.stats.maxWinStreak)" } ?? "—",
                systemImage: "flame.fill",
                color: .orange
            )
            statCard(
                title: "累計勝利",
                value: profile.map { "\($0.stats.totalWins)" } ?? "—",
                systemImage: "chart.bar.fill",
                color: Color(red: 0.20, green: 0.58, blue: 0.95)
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.subheadline.weight(.bold))

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.04, green: 0.07, blue: 0.14))
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.055), radius: 10, y: 5)
    }

    private var rulesCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 56, height: 56)
                .background(Color.blue.opacity(0.11), in: Circle())

            Rectangle()
                .fill(Color.gray.opacity(0.22))
                .frame(width: 1, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text("ルール")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.52))
                Text(CompetitiveClientDisplay.competitiveRuleSummary(for: profile))
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.32))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    private var startButton: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = CompetitiveForfeitCooldownPolicy.remainingSeconds(
                cooldownEndsAtEpochMS: cooldownEndsAtEpochMS,
                clientNowEpochMS: context.date.timeIntervalSince1970 * 1_000,
                serverTimeOffsetMS: serverTimeOffsetMS
            )
            Button(action: onStart) {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text(buttonTitle(remainingSeconds: remaining))
                        .font(.title3.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.57, blue: 1), Color.blue],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .shadow(color: Color.blue.opacity(0.24), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || remaining > 0)
            .opacity(isLoading || remaining > 0 ? 0.7 : 1)
        }
    }

    private func buttonTitle(remainingSeconds: Int) -> String {
        if remainingSeconds > 0 { return "再戦まで \(remainingSeconds)秒" }
        return isLoading ? "参加中…" : "対戦開始"
    }

    private func rankBadgeAssetName(for profile: CompetitiveProfileProjection) -> String {
        let stage = badgeStageOverride ?? CompetitiveClientDisplay.rankBadgeStage(for: profile)
        return CompetitiveClientDisplay.rankBadgeAssetName(
            tier: profile.currentTier,
            stage: stage
        )
    }

    private func tierAccentColor(_ tier: CompetitiveTier) -> Color {
        switch tier {
        case .bronze: Color(red: 0.25, green: 0.12, blue: 0.08)
        case .silver: Color(red: 0.31, green: 0.37, blue: 0.49)
        case .gold: Color(red: 0.73, green: 0.42, blue: 0.03)
        case .platinum: Color(red: 0.22, green: 0.37, blue: 0.78)
        case .ratingBattle: Color(red: 0.05, green: 0.20, blue: 0.55)
        }
    }

    @MainActor
    private func playBadgeEvolutionIfNeeded() async {
        guard let request = badgeEvolutionRequest,
              let profile,
              request.tier == profile.currentTier,
              CompetitiveClientDisplay.rankBadgeStage(for: profile) == .upper else { return }

        badgeStageOverride = .base
        badgeRotation = 0
        badgeScale = 1

        withAnimation(.easeIn(duration: 0.27)) {
            badgeRotation = 180
            badgeScale = 0.96
        }
        try? await Task.sleep(for: .milliseconds(270))
        guard !Task.isCancelled else { return }

        badgeStageOverride = .upper
        withAnimation(.easeOut(duration: 0.27)) {
            badgeRotation = 360
            badgeScale = 1
        }
        try? await Task.sleep(for: .milliseconds(270))
        guard !Task.isCancelled else { return }

        badgeStageOverride = nil
        badgeRotation = 0
        onBadgeEvolutionHandled(request.id)
    }

    @MainActor
    private func playTierChangeAnimationIfNeeded() async {
        guard let request = tierChangeAnimationRequest,
              let profile,
              request.tier == profile.currentTier else { return }

        badgeStageOverride = nil
        badgeRotation = 0
        badgeGlowOpacity = 0
        tierChangeLabel = request.direction == .promotion ? "ランク昇格！" : "ランク降格"
        tierChangeLabelOpacity = 0

        switch request.direction {
        case .promotion:
            badgeScale = 0.84
            badgeOpacity = 0.8
            withAnimation(.easeOut(duration: 0.35)) {
                badgeScale = 1.08
                badgeOpacity = 1
                badgeGlowOpacity = 0.6
                tierChangeLabelOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                badgeScale = 1
                badgeGlowOpacity = 0
                tierChangeLabelOpacity = 0
            }
        case .demotion:
            badgeScale = 1
            badgeOpacity = 0.3
            withAnimation(.easeOut(duration: 0.35)) {
                badgeOpacity = 1
                tierChangeLabelOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.35)) {
                tierChangeLabelOpacity = 0
            }
        }

        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        badgeScale = 1
        badgeOpacity = 1
        badgeGlowOpacity = 0
        tierChangeLabel = nil
        onTierChangeAnimationHandled(request.id)
    }
}
