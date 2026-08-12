import SwiftUI
import SwiftData

/// 学習タブ。カテゴリから学習内容を選ぶ入口
struct StudyHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("学習メニュー")
                    .font(.title3.bold())
                categorySelection
            }
            .padding()
        }
        .navigationTitle("学習")
    }

    private var categorySelection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                CategorySummaryView(category: .juniorHigh)
            } label: {
                StudyCategoryCard(
                    title: WordCategory.juniorHigh.displayName,
                    subtitle: "基礎から積み上げる",
                    systemImage: "books.vertical.fill",
                    accentColor: .blue,
                    backgroundColor: Color.blue.opacity(0.1)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                CategorySummaryView(category: .highSchool)
            } label: {
                StudyCategoryCard(
                    title: WordCategory.highSchool.displayName,
                    subtitle: "受験レベルまで対応",
                    systemImage: "graduationcap.fill",
                    accentColor: .orange,
                    backgroundColor: Color.orange.opacity(0.1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StudyCategoryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let backgroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(accentColor)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(backgroundColor))
    }
}

#Preview {
    NavigationStack {
        StudyHubView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self, StudyTimeTotal.self], inMemory: true)
}
