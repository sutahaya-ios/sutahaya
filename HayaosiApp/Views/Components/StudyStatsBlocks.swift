import SwiftUI

/// 習得率を円環で示す。マイページの学習記録で使う
struct ProficiencyRingBlock: View {
    private static let ringSize: CGFloat = 60
    private static let ringLineWidth: CGFloat = 7
    private static let progressColor = Color(
        red: 55.0 / 255.0,
        green: 138.0 / 255.0,
        blue: 221.0 / 255.0
    )

    let summary: CategoryProficiencySummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(
                        Color(.secondarySystemBackground),
                        lineWidth: Self.ringLineWidth
                    )

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Self.progressColor,
                        style: StrokeStyle(
                            lineWidth: Self.ringLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Self.ringSize, height: Self.ringSize)

            VStack(alignment: .leading, spacing: 2) {
                Text("習得率")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(rateText)
                    .font(.system(size: 24, weight: .medium))
                    .monospacedDigit()

                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progress: Double { summary.progress }
    private var rateText: String { summary.rateText }
    private var detailText: String { summary.detailText }
}

/// 直近12週の学習時間ヒートマップ
struct StudyTimeBlock: View {
    private static let gridSpacing: CGFloat = 3
    private static let cellSize: CGFloat = 14
    private static let cellCornerRadius: CGFloat = 2

    let summary: StudyTimeHeatmap.Summary
    /// 見出しを出すか。カード内で重複するときは false にする
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if showsTitle {
                    Text("学習時間")
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer(minLength: 8)

                Text("直近12週 · 計\(StudyDuration.text(seconds: summary.totalSeconds))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            heatmapGrid
                .padding(.top, 10)
        }
    }

    private var heatmapGrid: some View {
        HStack(spacing: Self.gridSpacing) {
            ForEach(summary.weeks.indices, id: \.self) { weekIndex in
                VStack(spacing: Self.gridSpacing) {
                    ForEach(summary.weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let day = summary.weeks[weekIndex][dayIndex] {
                            RoundedRectangle(cornerRadius: Self.cellCornerRadius)
                                .fill(day.level.color)
                                .frame(width: Self.cellSize, height: Self.cellSize)
                                .accessibilityHidden(true)
                        } else {
                            Color.clear
                                .frame(width: Self.cellSize, height: Self.cellSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("直近12週の学習時間、計\(StudyDuration.text(seconds: summary.totalSeconds))")
    }
}

/// 秒数を「◯時間◯分」へ整形する。学習時間の表示は必ずここを通す
enum StudyDuration {
    static func text(seconds: Double) -> String {
        let totalMinutes = Int(max(seconds, 0) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)分"
        }
        if minutes == 0 {
            return "\(hours)時間"
        }
        return "\(hours)時間\(minutes)分"
    }
}

extension StudyTimeHeatmap.Level {
    var color: Color {
        switch self {
        case .none:
            Color(.secondarySystemBackground)
        case .low:
            Color(red: 181.0 / 255.0, green: 212.0 / 255.0, blue: 244.0 / 255.0)
        case .medium:
            Color(red: 133.0 / 255.0, green: 183.0 / 255.0, blue: 235.0 / 255.0)
        case .high:
            Color(red: 55.0 / 255.0, green: 138.0 / 255.0, blue: 221.0 / 255.0)
        case .highest:
            Color(red: 24.0 / 255.0, green: 95.0 / 255.0, blue: 165.0 / 255.0)
        }
    }
}
