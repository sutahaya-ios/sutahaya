import SwiftUI
import SwiftData

/// 設定(ニックネーム・学習データ管理)。要件 §9-7
struct SettingsView: View {
    /// 連続入力中に毎回Firestoreへ書き込まないための待ち時間
    private static let nicknameSyncDelay: TimeInterval = 1.0

    @AppStorage("nickname") private var nickname = "ゲスト"
    @AppStorage(SoundPlayer.enabledKey) private var soundEnabled = true
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteDialog = false
    @State private var nicknameSyncTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("ニックネーム", text: $nickname)
            } header: {
                Text("プロフィール")
            } footer: {
                Text("対戦時に他の参加者へ表示される名前です")
            }

            Section {
                Toggle("効果音", isOn: $soundEnabled)
                Toggle("振動(ハプティクス)", isOn: $hapticsEnabled)
            } header: {
                Text("サウンド")
            } footer: {
                Text("効果音はマナーモード中は鳴りません")
            }

            Section("学習データ") {
                Button("解答履歴と復習リストを削除", role: .destructive) {
                    showDeleteDialog = true
                }
            }

            Section("アプリ情報") {
                LabeledContent("バージョン", value: "0.5.0")
            }
        }
        .navigationTitle("設定")
        .onChange(of: nickname) { _, newNickname in
            scheduleNicknameSync(newNickname)
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
    }

    /// オンラインプロフィール(users/{uid})へニックネームを反映する
    private func scheduleNicknameSync(_ newNickname: String) {
        nicknameSyncTask?.cancel()
        nicknameSyncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.nicknameSyncDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await AuthService.shared.updateNicknameIfSignedIn(newNickname)
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
