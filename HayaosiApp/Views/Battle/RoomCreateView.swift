import SwiftUI
import SwiftData

/// ルーム作成:設定を決めてルームを発行し、待機ロビーへ(要件 §5.1.1・§9-3)
struct RoomCreateView: View {
    enum Mode: Equatable {
        case create
        case editPreferences
        case editRoom
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var configuration: OnlineRoomConfiguration
    @State private var session: OnlineBattleSession?
    @State private var isCreating = false
    @State private var showRoom = false
    @State private var errorMessage: String?
    @State private var settingsUpdateTask: Task<Void, Error>?

    private let mode: Mode
    private let synchronizesChangesImmediately: Bool
    private let onSaveSettings: (@MainActor (RoomState.Settings) async throws -> Void)?

    init(
        mode: Mode = .create,
        initialConfiguration: OnlineRoomConfiguration? = nil,
        synchronizesChangesImmediately: Bool = false,
        onSaveSettings: (@MainActor (RoomState.Settings) async throws -> Void)? = nil
    ) {
        self.mode = mode
        self.synchronizesChangesImmediately = synchronizesChangesImmediately
        self.onSaveSettings = onSaveSettings
        _configuration = State(initialValue: initialConfiguration ?? OnlineRoomConfiguration())
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
        .navigationTitle(mode == .create ? "ルーム作成" : "対戦設定")
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
        .onChange(of: configuration) { _, newConfiguration in
            guard mode == .editRoom, synchronizesChangesImmediately else { return }
            synchronizeRoomSettings(newConfiguration)
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
                switch mode {
                case .editPreferences:
                    configuration.save()
                    dismiss()
                case .editRoom:
                    Task { await saveRoomSettings() }
                case .create:
                    Task { await create() }
                }
            } label: {
                Group {
                    if isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode == .create ? "ルームを作成" : "この設定を使う")
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

    private func saveRoomSettings() async {
        guard let updateTask = enqueueRoomSettingsUpdate(configuration) else { return }

        isCreating = true
        defer { isCreating = false }
        do {
            try await updateTask.value
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func synchronizeRoomSettings(_ configuration: OnlineRoomConfiguration) {
        guard let updateTask = enqueueRoomSettingsUpdate(configuration) else { return }
        Task { @MainActor in
            do {
                try await updateTask.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Pickerを続けて変更しても、古い設定のwriteが新しい設定を追い越さないよう直列化する。
    private func enqueueRoomSettingsUpdate(
        _ configuration: OnlineRoomConfiguration
    ) -> Task<Void, Error>? {
        let availableQuestionCount = allQuestions
            .filter { $0.genre == .englishWord }
            .matching(
                category: configuration.category,
                difficulty: configuration.difficulty
            )
            .count
        guard availableQuestionCount > 0, let onSaveSettings else { return nil }

        let previousTask = settingsUpdateTask
        let settings = configuration.roomSettings(
            availableQuestionCount: availableQuestionCount
        )
        let updateTask = Task { @MainActor in
            _ = try? await previousTask?.value
            try await onSaveSettings(settings)
        }
        settingsUpdateTask = updateTask
        return updateTask
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
