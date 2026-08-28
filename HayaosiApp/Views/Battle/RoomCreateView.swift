import SwiftUI
import SwiftData

/// ルーム作成:設定を決めてルームを発行し、待機ロビーへ(要件 §5.1.1・§9-3)
struct RoomCreateView: View {
    enum Mode: Equatable {
        case create
        case editPreferences
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var configuration: OnlineRoomConfiguration
    @State private var session: OnlineBattleSession?
    @State private var isCreating = false
    @State private var showRoom = false
    @State private var errorMessage: String?

    private let mode: Mode

    init(mode: Mode = .create) {
        self.mode = mode
        _configuration = State(initialValue: OnlineRoomConfiguration())
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("ジャンル", value: Genre.englishWord.displayName)
                WordClassificationPicker(
                    category: $configuration.category,
                    difficulty: $configuration.difficulty
                )
                Picker("問題数", selection: $configuration.questionCount) {
                    ForEach(QuizDefaults.questionCountOptions, id: \.self) { count in
                        Text("\(count)問").tag(count)
                    }
                }
                Picker("制限時間", selection: $configuration.timeLimit) {
                    ForEach(QuizDefaults.timeLimitOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))秒 / 問").tag(seconds)
                    }
                }
            } header: {
                Text("対戦設定")
            } footer: {
                Text("\(configuration.category.displayName) \(configuration.difficulty.starDisplay)の収録問題数:\(availableQuestions.count)問\n設定した問題数に満たない場合は、収録されている問題だけを出題します。")
            }

            if availableQuestions.isEmpty {
                Section {
                    QuestionAvailabilityNotice(
                        category: configuration.category,
                        difficulty: configuration.difficulty
                    )
                }
            } else {
                Section {
                    Button {
                        if mode == .editPreferences {
                            configuration.save()
                            dismiss()
                        } else {
                            Task { await create() }
                        }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(mode == .editPreferences ? "この設定を使う" : "ルームを作成")
                        }
                    }
                    .buttonStyle(SoundButtonStyle())
                    .disabled(isCreating)
                } footer: {
                    Text("作成すると参加コードが発行されます。同じ部屋の友達も遠隔の友達も、コード入力で入室できます。")
                }
            }
        }
        .navigationTitle(mode == .editPreferences ? "対戦設定" : "ルーム作成")
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
            .matching(
                category: configuration.category,
                difficulty: configuration.difficulty
            )
    }

    private func create() async {
        let availableQuestionCount = availableQuestions.count
        guard availableQuestionCount > 0 else { return }

        isCreating = true
        defer { isCreating = false }
        do {
            configuration.save()
            let uid = try await AuthService.shared.ensureSignedIn()
            let newSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            try await newSession.createRoom(
                settings: configuration.roomSettings(
                    availableQuestionCount: availableQuestionCount
                )
            )
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
