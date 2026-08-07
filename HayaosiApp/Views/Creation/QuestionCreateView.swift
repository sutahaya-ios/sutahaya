import SwiftUI

/// 作問タブ。ユーザーが自分で問題を作れるようにする機能で、**次回アップデートで実装予定**。
/// いまは何ができるようになるかだけを見せる(要件 §4 v1.5「ユーザー投稿問題」)
struct QuestionCreateView: View {
    private static let plans: [(icon: String, title: String, detail: String)] = [
        ("square.and.pencil", "自分で問題を作る", "覚えたい単語と意味を登録して、自分だけの問題セットにできます"),
        ("person.2.fill", "友達と共有する", "作った問題セットを友達に渡して、そのまま対戦できます"),
        ("books.vertical.fill", "テスト範囲に合わせる", "授業や試験の範囲だけを集めた出題ができます")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                VStack(spacing: 12) {
                    ForEach(Self.plans, id: \.title) { plan in
                        planRow(plan)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("作問")
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("次回アップデートで公開予定")
                .font(.headline)
            Text("いまは収録済みの英単語で対戦できます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func planRow(_ plan: (icon: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: plan.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title)
                    .font(.headline)
                Text(plan.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    NavigationStack {
        QuestionCreateView()
    }
}
