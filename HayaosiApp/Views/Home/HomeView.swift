import SwiftUI
import SwiftData

/// ホームタブ:一人練習への導線と成績サマリ(要件 §9-1)
struct HomeView: View {
    @Query private var records: [AnswerRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("勉強×早押し対戦(仮称)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                .buttonStyle(.plain)

                statsCard
            }
            .padding()
        }
        .navigationTitle("HayaosiApp")
    }

    private var totalCount: Int { records.count }
    private var correctCount: Int { records.filter(\.isCorrect).count }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("これまでの成績")
                .font(.headline)

            if totalCount == 0 {
                Text("まだ解答がありません。一人練習から始めてみよう!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    statItem(value: "\(totalCount)", label: "総解答数")
                    statItem(value: "\(correctCount)", label: "正解数")
                    statItem(
                        value: "\(Int(Double(correctCount) / Double(totalCount) * 100))%",
                        label: "正答率"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
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
        HomeView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
