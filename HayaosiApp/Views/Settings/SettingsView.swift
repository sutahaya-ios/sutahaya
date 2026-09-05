import SwiftUI
import SwiftData

enum SettingsContent {
    case all
    case profile
    case soundAndHaptics
    case learningData

    var title: String {
        switch self {
        case .all: "設定"
        case .profile: "プロフィール編集"
        case .soundAndHaptics: "サウンド・振動"
        case .learningData: "学習データ"
        }
    }
}

/// 設定(ニックネーム・学習データ管理)。要件 §9-7
struct SettingsView: View {
    /// 連続入力中に毎回Firestoreへ書き込まないための待ち時間
    private static let profileSyncDelay: TimeInterval = 1.0
    /// 自己紹介の最大文字数(将来Firestoreへ同期する際の上限とも一致させる)
    private static let bioMaxLength = 140
    private static let nicknameMaxLength = ProfileInputPolicy.nicknameMaxLength

    @AppStorage("nickname") private var nickname = "ゲスト"
    @AppStorage("profileIcon") private var profileIcon = ProfileIcon.none
    @AppStorage("profileBio") private var bio = ""
    @AppStorage(SoundPlayer.enabledKey) private var soundEnabled = true
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteDialog = false
    @State private var profileSyncTask: Task<Void, Never>?
    var content: SettingsContent = .all

    var body: some View {
        Form {
            if content == .all || content == .profile {
                profileSection
            }

            if content == .all || content == .soundAndHaptics {
                soundSection
            }

            if content == .all || content == .learningData {
                learningDataSection
            }
        }
        .navigationTitle(content.title)
        .onChange(of: nickname) { _, newNickname in
            if newNickname.count > Self.nicknameMaxLength {
                nickname = String(newNickname.prefix(Self.nicknameMaxLength))
                return
            }
            scheduleProfileSync()
        }
        .onChange(of: profileIcon) { _, _ in
            scheduleProfileSync()
        }
        .onChange(of: bio) { _, newBio in
            if newBio.count > Self.bioMaxLength {
                bio = String(newBio.prefix(Self.bioMaxLength))
                return
            }
            scheduleProfileSync()
        }
        .confirmationDialog(
            "解答履歴と復習リストをすべて削除しますか?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                deleteLearningData()
            }
        }
        .onDisappear {
            nickname = ProfileInputPolicy.normalizedNickname(nickname)
        }
    }

    private var profileSection: some View {
        Section {
            TextField("ニックネーム", text: $nickname)

            ProfileIconPicker(selection: $profileIcon)
                .padding(.vertical, 4)

            TextField("自己紹介(任意)", text: $bio, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text("プロフィール")
        } footer: {
            Text("名前・アイコン・自己紹介はオンラインプロフィールへ反映されます")
        }
    }

    private var soundSection: some View {
        Section {
            Toggle("効果音", isOn: $soundEnabled)
            Toggle("振動(ハプティクス)", isOn: $hapticsEnabled)
        } header: {
            Text("サウンド")
        } footer: {
            Text("効果音はマナーモード中は鳴りません")
        }
    }

    private var learningDataSection: some View {
        Section("学習データ") {
            Button("解答履歴と復習リストを削除", role: .destructive) {
                showDeleteDialog = true
            }
        }
    }

    /// オンラインプロフィール(users/{uid})へ連続入力をまとめて反映する
    private func scheduleProfileSync() {
        profileSyncTask?.cancel()
        let latestNickname = nickname
        let latestIcon = profileIcon
        let latestBio = bio
        profileSyncTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.profileSyncDelay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await AuthService.shared.updateProfileIfSignedIn(
                nickname: latestNickname,
                icon: latestIcon,
                bio: latestBio
            )
        }
    }

    private func deleteLearningData() {
        do {
            try modelContext.delete(model: AnswerRecord.self)
            try modelContext.delete(model: ReviewItem.self)
            try modelContext.save()
        } catch {
            print("学習データの削除に失敗: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self], inMemory: true)
}
