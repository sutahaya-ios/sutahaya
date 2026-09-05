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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modeSection

                BattleSettingsSelector(
                    configuration: $configuration,
                    availableWordCount: availableQuestions.count
                )

                if availableQuestions.isEmpty {
                    QuestionAvailabilityNotice(
                        category: configuration.category,
                        difficulty: configuration.difficulty
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if !availableQuestions.isEmpty {
                primaryControl
            }
        }
        .navigationTitle(mode == .editPreferences ? "対戦設定" : "ルーム作成")
        .navigationBarTitleDisplayMode(.inline)
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

    /// 出題の種類。いまは英単語だけだが、増えたときにここが伸びる
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("モード")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Picker("モード", selection: .constant(Genre.englishWord)) {
                ForEach(Genre.allCases) { genre in
                    Text(genre.displayName).tag(genre)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var primaryControl: some View {
        VStack(spacing: 8) {
            if mode == .create {
                Text("作成すると参加コードが発行されます。同じ部屋の友達も遠隔の友達も、コード入力で入室できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if mode == .editPreferences {
                    configuration.save()
                    dismiss()
                } else {
                    Task { await create() }
                }
            } label: {
                Group {
                    if isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode == .editPreferences ? "この設定を使う" : "ルームを作成")
                            .font(.headline.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(SoundButtonStyle())
            .disabled(isCreating)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
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
            let uid = try await AuthService.shared.ensureAuthenticated()
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
