import SwiftUI

/// 1問目の前に表示する、CPU・オンライン共通の開始合図
struct BattleStartView: View {
    /// server開始時刻の受信前はnil。受信後は0...1の進捗を表示する。
    let progress: Double?

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

            if let progress {
                ProgressView(value: progress)
                    .tint(.orange)
                    .frame(maxWidth: 180)
            } else {
                ProgressView()
                    .tint(.orange)
            }

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
