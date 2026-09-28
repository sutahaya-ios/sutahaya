import SwiftUI

/// 対戦設定の4項目を一覧しつつ、選んだ1項目の選択肢だけを出す。
/// 並びとアイコンはロビーの設定カードに合わせ、画面をまたいでも同じものが同じ形で見えるようにする
struct BattleSettingsSelector: View {
    /// 4分割で切り替える対象
    private enum Axis: Hashable {
        case category
        case difficulty
        case questionCount
        case timeLimit

        var title: String {
            switch self {
            case .category: return "ジャンル"
            case .difficulty: return "レベル"
            case .questionCount: return "問題数"
            case .timeLimit: return "制限時間"
            }
        }

        var systemImage: String {
            switch self {
            case .category: return "book"
            case .difficulty: return "star"
            case .questionCount: return "list.bullet"
            case .timeLimit: return "clock"
            }
        }
    }

    private static let cardCornerRadius: CGFloat = 18
    private static let cellCornerRadius: CGFloat = 12

    @Binding var configuration: OnlineRoomConfiguration
    /// いまの設定で出題できる語数
    let availableWordCount: Int

    /// 開いた直後は必ずジャンル。選択位置が毎回動くと、選ぶ場所を探すことになるため固定する
    @State private var selectedAxis: Axis = .category

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            axisCard
            options
            availabilityRow
        }
    }

    // MARK: - 4分割

    private var axisCard: some View {
        HStack(spacing: 0) {
            axisCell(.category)
            cellDivider
            axisCell(.difficulty)
            cellDivider
            axisCell(.questionCount)
            cellDivider
            axisCell(.timeLimit)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        )
    }

    private var cellDivider: some View {
        Divider().frame(height: 46)
    }

    private func axisCell(_ axis: Axis) -> some View {
        Button {
            selectedAxis = axis
        } label: {
            VStack(spacing: 5) {
                Image(systemName: axis.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(axis.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value(for: axis))
                    .font(.footnote.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selectedAxis == axis {
                    RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous))
        }
        .buttonStyle(SoundButtonStyle())
        .accessibilityLabel("\(axis.title) \(value(for: axis))")
        .accessibilityHint("選択肢を表示します")
    }

    private func value(for axis: Axis) -> String {
        switch axis {
        case .category: return configuration.category.displayName
        case .difficulty: return "★\(configuration.difficulty.rawValue)"
        case .questionCount: return "\(configuration.questionCount)問"
        case .timeLimit: return "\(Int(configuration.timeLimit))秒"
        }
    }

    // MARK: - 選択肢

    @ViewBuilder
    private var options: some View {
        switch selectedAxis {
        case .category:
            chips(configuration.genre.categories, current: configuration.category) {
                $0.displayName
            } select: {
                configuration.category = $0
            }
        case .difficulty:
            chips(StudyDifficulty.allCases, current: configuration.difficulty) {
                "★\($0.rawValue)"
            } select: {
                configuration.difficulty = $0
            }
        case .questionCount:
            chips(QuizDefaults.questionCountOptions, current: configuration.questionCount) {
                "\($0)問"
            } select: {
                configuration.questionCount = $0
            }
        case .timeLimit:
            chips(
                QuizDefaults.timeLimitOptions(for: configuration.category),
                current: configuration.timeLimit
            ) {
                "\(Int($0))秒"
            } select: {
                configuration.timeLimit = $0
            }
        }
    }

    private func chips<Value: Hashable>(
        _ values: [Value],
        current: Value,
        label: @escaping (Value) -> String,
        select: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button {
                    select(value)
                } label: {
                    Text(label(value))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            current == value
                                ? Color.accentColor
                                : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous)
                        )
                        .foregroundStyle(current == value ? Color.white : Color.primary)
                        .contentShape(RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous))
                }
                .buttonStyle(SoundButtonStyle())
            }
        }
    }

    // MARK: - 出題できる語数

    /// 設定した問題数に足りないときだけ色で気付かせる(説明文は出さない)
    private var isShortOfQuestions: Bool {
        availableWordCount < configuration.questionCount
    }

    private var availabilityRow: some View {
        HStack(spacing: 8) {
            Text("この設定で出せる問題")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("\(availableWordCount)\(configuration.category.questionUnit)")
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(isShortOfQuestions ? Color.orange : Color.primary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var configuration = OnlineRoomConfiguration.default

    return BattleSettingsSelector(configuration: $configuration, availableWordCount: 300)
        .padding()
        .background(Color(.systemGroupedBackground))
}
