import SwiftUI
import SwiftData

/// 学習タブ。一人練習・復習・学習成果を1か所にまとめる
struct StudyHubView: View {
    @Query private var records: [AnswerRecord]

    private var totalCount: Int { records.count }
    private var correctCount: Int { records.filter(\.isCorrect).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                learningMenu

                VStack(alignment: .leading, spacing: 12) {
                    Text("これまでの成績")
                        .font(.title3.bold())
                    statsCard
                }
            }
            .padding()
        }
        .navigationTitle("学習")
    }

    private var learningMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("学習メニュー")
                .font(.title3.bold())

            NavigationLink {
                PracticeSetupView()
            } label: {
                MenuCard(
                    title: "一人練習",
                    subtitle: "オフラインでサクッと練習",
                    systemImage: "person.fill",
                    color: .blue
                )
            }
            .buttonStyle(SoundButtonStyle())

            NavigationLink {
                ReviewListView()
            } label: {
                MenuCard(
                    title: "復習リスト",
                    subtitle: "間違えた問題をもう一度",
                    systemImage: "arrow.counterclockwise",
                    color: .green
                )
            }
            .buttonStyle(SoundButtonStyle())
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if totalCount == 0 {
                Text("まだ解答がありません。一人練習から始めてみよう!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    statItem(value: "\(totalCount)", label: "総解答数")
                    statItem(value: "\(correctCount)", label: "正解数")
                    statItem(value: "\(correctRate)%", label: "正答率")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var correctRate: Int {
        guard totalCount > 0 else { return 0 }
        return Int(Double(correctCount) / Double(totalCount) * 100)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        StudyHubView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
