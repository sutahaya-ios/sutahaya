import SwiftUI

/// Firebase未設定時に、サンプルデータでUIを表示していることを知らせるバナー
struct OnlinePreviewBanner: View {
    var body: some View {
        Label("オンライン未設定のためサンプル表示中(設定手順:FIREBASE_SETUP.md)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}
