import SwiftUI

/// 1問目の前に表示する、CPU・オンライン共通の開始合図
struct BattleStartView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 96, height: 96)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("対戦開始！")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            ProgressView(value: progress)
                .tint(.orange)
                .frame(maxWidth: 180)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("対戦")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("対戦開始")
    }
}

#Preview {
    NavigationStack {
        BattleStartView(progress: 0.6)
    }
}
