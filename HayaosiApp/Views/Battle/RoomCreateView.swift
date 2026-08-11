import SwiftUI
import SwiftData

/// ルーム作成:設定を決めてルームを発行し、待機ロビーへ(要件 §5.1.1・§9-3)
struct RoomCreateView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var category = WordCategory.juniorHigh
    @State private var difficulty = WordDifficulty.one
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var session: OnlineBattleSession?
    @State private var isCreating = false
    @State private var showRoom = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("ジャンル", selection: .constant(Genre.englishWord)) {
                    ForEach(Genre.allCases) { genre in
                        Text(genre.displayName).tag(genre)
                    }
                }
                WordClassificationPicker(category: $category, difficulty: $difficulty)
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
            } header: {
                Text("対戦設定")
            } footer: {
                Text("\(category.displayName) \(difficulty.starDisplay)の収録問題数:\(availableQuestions.count)問\n設定した問題数に満たない場合は、収録されている問題だけを出題します。")
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("ルームを作成")
                    }
                }
                .buttonStyle(SoundButtonStyle())
                .disabled(isCreating || availableQuestions.isEmpty)
            } footer: {
                Text("作成すると参加コードが発行されます。同じ部屋の友達も遠隔の友達も、コード入力で入室できます。")
            }
        }
        .navigationTitle("ルーム作成")
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
        .alert("エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var availableQuestions: [Question] {
        allQuestions
            .filter { $0.genre == .englishWord }
            .matching(category: category, difficulty: difficulty)
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            let newSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            try await newSession.createRoom(settings: .init(
                questionCount: min(questionCount, availableQuestions.count),
                timeLimit: timeLimit,
                genre: .englishWord,
                wordCategory: category,
                wordDifficulty: difficulty
            ))
            session = newSession
            showRoom = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RoomCreateView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
