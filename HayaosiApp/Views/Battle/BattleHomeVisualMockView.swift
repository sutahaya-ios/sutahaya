import SwiftUI
import UIKit

/// 対戦ホームのVisual Designだけを確認する、既存フローから独立したモック。
struct BattleHomeVisualMockView: View {
    private let background = Color(red: 248 / 255, green: 247 / 255, blue: 243 / 255)
    private let brandBlue = Color(red: 66 / 255, green: 107 / 255, blue: 211 / 255)
    private let charcoal = Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("スタはや")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(charcoal.opacity(0.72))

                Text("今日は誰と対戦する？")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(charcoal)
                    .padding(.top, 30)

                HStack(spacing: 14) {
                    CompressingActionSurface(
                        title: "フレンドバトル",
                        surfaceColor: Color(red: 236 / 255, green: 235 / 255, blue: 230 / 255),
                        symbol: { FacingCoreSymbol() },
                        action: {}
                    )

                    StandbyActionSurface()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("現在の設定")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(charcoal.opacity(0.46))

                        Spacer()

                        Button("変更") {}
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(brandBlue)
                    }

                    Text("高校英単語 ★3・10問・5秒")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(charcoal.opacity(0.88))
                }
                .padding(.top, 44)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)

            mockTabBar
        }
        .background(background.ignoresSafeArea())
    }

    private var mockTabBar: some View {
        HStack {
            mockTab("対戦", selected: true)
            mockTab("学習", selected: false)
            mockTab("マイページ", selected: false)
        }
        .frame(height: 54)
        .background(background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(charcoal.opacity(0.07))
                .frame(height: 1)
        }
    }

    private func mockTab(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? brandBlue : charcoal.opacity(0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompressingActionSurface<Symbol: View>: View {
    let title: String
    let surfaceColor: Color
    @ViewBuilder let symbol: () -> Symbol
    let action: () -> Void

    @State private var isPressed = false
    @State private var hapticTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.055))
                .frame(width: 158, height: 88)
                .offset(y: 1.5)

            VStack(spacing: 7) {
                symbol()
                    .frame(width: 30, height: 24)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255))
                    .lineLimit(1)
            }
            .frame(width: 158, height: isPressed ? 86 : 88)
            .background(surfaceColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .offset(y: isPressed ? 2.5 : 0)
        }
        .frame(width: 158, height: 91, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressDownIfNeeded()
                }
                .onEnded { value in
                    release(activate: abs(value.translation.width) < 24 && abs(value.translation.height) < 24)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
        }
    }

    private func pressDownIfNeeded() {
        guard !isPressed else { return }
        withAnimation(.easeOut(duration: 0.09)) {
            isPressed = true
        }
        hapticTask?.cancel()
        hapticTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, isPressed else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        }
    }

    private func release(activate: Bool) {
        hapticTask?.cancel()
        withAnimation(.spring(duration: 0.12, bounce: 0.12)) {
            isPressed = false
        }
        if activate {
            action()
        }
    }
}

private struct StandbyActionSurface: View {
    var body: some View {
        VStack(spacing: 4) {
            ConnectedFacingCoreSymbol()
                .frame(width: 30, height: 24)

            Text("オンライン対戦")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Text("乞うご期待")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255).opacity(0.46))
        }
        .foregroundStyle(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255).opacity(0.72))
        .frame(width: 158, height: 88)
        .background(
            Color(red: 227 / 255, green: 226 / 255, blue: 221 / 255),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .frame(width: 158, height: 91, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// 2つの面が同じ中心へ向かう、対戦の抽象記号。
private struct FacingCoreSymbol: View {
    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255).opacity(0.82))
                .frame(width: 11, height: 18)
                .rotationEffect(.degrees(-18))

            Circle()
                .fill(Color(red: 66 / 255, green: 107 / 255, blue: 211 / 255))
                .frame(width: 5, height: 5)

            Capsule()
                .fill(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255).opacity(0.82))
                .frame(width: 11, height: 18)
                .rotationEffect(.degrees(18))
        }
    }
}

/// 対向Coreの外側に候補点を加え、接続待ちを最小限に表す記号。
private struct ConnectedFacingCoreSymbol: View {
    var body: some View {
        ZStack {
            FacingCoreSymbol()

            Circle()
                .fill(Color(red: 34 / 255, green: 35 / 255, blue: 32 / 255).opacity(0.38))
                .frame(width: 4, height: 4)
                .offset(x: 15, y: -8)
        }
    }
}

#Preview("Battle Home Visual Mock") {
    BattleHomeVisualMockView()
}
