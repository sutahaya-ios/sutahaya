import SwiftUI

/// CPU対戦の設定画面。Firebase不要でロビー→対戦→リザルトの流れを試せる
struct CPUBattleSetupView: View {
    private static let botCountRange = 1...3

    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var style = QuizDefaults.style
    @State private var cpuCount = 2
    @State private var session: CPUBattleSession?
    @State private var showRoom = false

    var body: some View {
        Form {
            Section {
                QuizStylePicker(style: $style)
            } header: {
                Text("対戦形式")
            } footer: {
                Text(style.detail)
            }

            Section("対戦設定") {
                Picker("ジャンル", selection: .constant(Genre.englishWord)) {
                    ForEach(Genre.allCases) { genre in
                        Text(genre.displayName).tag(genre)
                    }
                }
                Picker("問題数", selection: $questionCount) {
                    ForEach(QuizDefaults.questionCountOptions, id: \.self) { count in
                        Text("\(count)問").tag(count)
                    }
                }
                Picker("制限時間", selection: $timeLimit) {
                    ForEach(QuizDefaults.timeLimitOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))秒 / 問").tag(seconds)
                    }
                }
                Stepper("CPU \(cpuCount)体", value: $cpuCount, in: Self.botCountRange)
            }

            Section {
                Button("ロビーへ") {
                    start()
                }
            } footer: {
                Text("通信なしでCPUと早押し対戦できます。結果は一人練習として学習履歴・復習リストに記録されます。")
            }
        }
        .navigationTitle("ひとりで(CPU対戦)")
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                BattleFlowView(session: session)
            }
        }
        .onChange(of: showRoom) { _, isShowing in
            if !isShowing {
                session?.leave()
                session = nil
            }
        }
    }

    private func start() {
        session = CPUBattleSession(
            nickname: nickname,
            settings: .init(
                questionCount: questionCount,
                timeLimit: timeLimit,
                genre: .englishWord,
                style: style
            ),
            cpuCount: cpuCount
        )
        showRoom = true
    }
}

#Preview {
    NavigationStack {
        CPUBattleSetupView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
