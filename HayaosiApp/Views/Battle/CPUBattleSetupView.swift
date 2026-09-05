import SwiftUI
import SwiftData

/// NPC対戦の設定画面。Firebase不要でロビー→対戦→リザルトの流れを試せる。
struct CPUBattleSetupView: View {
    private static let botCountRange = 1...(BattleRules.maxPlayers - 1)

    @AppStorage("nickname") private var nickname = "ゲスト"
    @Query private var allQuestions: [Question]
    @State private var category = WordCategory.juniorHigh
    @State private var difficulty = WordDifficulty.one
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var cpuCount = 2
    @State private var session: CPUBattleSession?
    @State private var showRoom = false

    var body: some View {
        Form {
            Section("対戦設定") {
                LabeledContent("ジャンル", value: Genre.englishWord.displayName)
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
                Stepper("NPC \(cpuCount)体", value: $cpuCount, in: Self.botCountRange)
            }

            if availableQuestions.isEmpty {
                Section {
                    QuestionAvailabilityNotice(category: category, difficulty: difficulty)
                }
            } else {
                Section {
                    Button("ロビーへ") {
                        start()
                    }
                    .buttonStyle(SoundButtonStyle())
                } footer: {
                    Text("\(category.displayName) \(difficulty.starDisplay)の収録問題数:\(availableQuestions.count)問\n設定した問題数に満たない場合は、収録されている問題だけを出題します。")
                }
            }
        }
        .navigationTitle("NPCと対戦")
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                CPUBattleRoomView(session: session)
            }
        }
        .onChange(of: showRoom) { _, isShowing in
            if !isShowing {
                session?.leave()
                session = nil
            }
        }
    }

    private var availableQuestions: [Question] {
        allQuestions
            .filter { $0.genre == .englishWord }
            .matching(category: category, difficulty: difficulty)
    }

    private func start() {
        let availableQuestionCount = availableQuestions.count
        guard availableQuestionCount > 0 else { return }
        session = CPUBattleSession(
            nickname: nickname,
            settings: .init(
                questionCount: min(questionCount, availableQuestionCount),
                timeLimit: timeLimit,
                genre: .englishWord,
                wordCategory: category,
                wordDifficulty: difficulty
            ),
            cpuProfiles: Array(CPUProfile.roster.prefix(cpuCount))
        )
        showRoom = true
    }
}

/// ローカルルームにだけNPC管理を足し、共通の対戦フローはそのまま再利用する。
struct CPUBattleRoomView: View {
    let session: CPUBattleSession

    @State private var showNPCManagement = false

    var body: some View {
        BattleFlowView(session: session)
            .toolbar {
                if session.isHost, session.state?.status == .waiting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showNPCManagement = true
                        } label: {
                            Label("NPC管理", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(SoundButtonStyle())
                    }
                }
            }
            .sheet(isPresented: $showNPCManagement) {
                NavigationStack {
                    NPCManagementView(session: session)
                }
                .presentationDetents([.medium, .large])
            }
    }
}

/// ホストが待機中のローカルルームに、既存プロファイルのNPCを追加・削除する。
private struct NPCManagementView: View {
    let session: CPUBattleSession

    @Environment(\.dismiss) private var dismiss

    private var availableProfiles: [CPUProfile] {
        let joinedIDs = Set(session.cpuProfiles.map(\.id))
        return CPUProfile.roster.filter { !joinedIDs.contains($0.id) }
    }

    private var memberCount: Int {
        session.state?.players.count ?? 1
    }

    var body: some View {
        List {
            Section("参加中 \(memberCount)/\(BattleRules.maxPlayers)") {
                if session.cpuProfiles.isEmpty {
                    Text("NPCはいません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.cpuProfiles) { profile in
                        HStack(spacing: 12) {
                            AvatarCircle(
                                name: profile.nickname,
                                icon: "",
                                size: 42,
                                color: .accentColor
                            )
                            profileDescription(profile)
                            Spacer()
                            if session.isHost {
                                Button(role: .destructive) {
                                    session.removeCPU(id: profile.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(SoundButtonStyle())
                                .accessibilityLabel("\(profile.nickname)を削除")
                            }
                        }
                    }
                }
            }

            if session.isHost {
                Section("NPCを追加") {
                    if memberCount >= BattleRules.maxPlayers {
                        Label("\(BattleRules.maxPlayers)人まで参加できます", systemImage: "person.3.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableProfiles) { profile in
                            Button {
                                session.addCPU(profile)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 42, height: 42)
                                    profileDescription(profile)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SoundButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationTitle("NPC管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
    }

    private func profileDescription(_ profile: CPUProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.nickname)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(profile.strengthDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        CPUBattleSetupView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
