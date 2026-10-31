import SwiftUI

/// 作成した問題集と受信した共有の入口。
struct QuestionCreateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = QuestionSetService()
    @State private var isCreating = false
    @State private var addingIDs: Set<String> = []
    @State private var actionError = ""
    @State private var showsActionError = false

    var body: some View {
        List {
            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("問題集を新規作成", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.vertical, 6)
                }
                .disabled(service.uid == nil || service.isLoading)
                .accessibilityIdentifier("authoring.newSet")
            } footer: {
                Text("○×・4択・短い記述の問題集を作り、フレンドに共有できます。")
            }

            if service.isLoading {
                Section { ProgressView("問題集を読み込み中…") }
            }
            if let errorMessage = service.errorMessage {
                Section {
                    Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorMessage).font(.subheadline)
                    Button("再試行") { Task { await service.load() } }
                        .disabled(service.isLoading)
                        .accessibilityIdentifier("authoring.retry")
                }
            }

            if let warningMessage = service.warningMessage {
                Section {
                    Label("一部の問題集を表示できません", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(warningMessage).font(.subheadline)
                }
                .accessibilityIdentifier("authoring.warning")
            }

            Section("ライブラリ") {
                ForEach(service.library) { set in
                    NavigationLink {
                        QuestionSetDetailView(questionSetID: set.id, service: service)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(set.title).font(.headline)
                            Text("\(set.questions.count)問 · \(set.creatorUID == service.uid ? "自分で作成" : "フレンドから追加")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("authoring.library.\(set.id)")
                }
                if service.library.isEmpty && !service.isLoading && service.errorMessage == nil {
                    ContentUnavailableView(
                        "問題集を作ってみましょう", systemImage: "books.vertical",
                        description: Text("「問題集を新規作成」から、覚えたい問題を登録できます。")
                    )
                }
            }

            Section("フレンドからの共有") {
                ForEach(service.sharedSets) { share in
                    sharedRow(share)
                }
                if service.sharedSets.isEmpty && !service.isLoading && service.errorMessage == nil {
                    Text("共有された問題集はありません。届いた問題集はここからライブラリに追加できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("作問")
        .accessibilityIdentifier("authoring.library")
        .task { await service.load() }
        .refreshable { await service.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await service.load() } }
        }
        .sheet(isPresented: $isCreating) {
            QuestionSetEditorView(service: service)
        }
        .alert("追加できませんでした", isPresented: $showsActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError)
        }
    }

    private func sharedRow(_ share: QuestionSetShare) -> some View {
        let isAvailable = service.questionSets[share.questionSetID]?.status == .active
        let isAdded = service.libraryIDs.contains(share.questionSetID)
        return VStack(alignment: .leading, spacing: 10) {
            Text(share.title).font(.headline)
            Text("\(share.fromNickname)さんから共有されました")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !isAvailable {
                Label("この問題集は現在利用できません", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isAdded {
                Label("ライブラリに追加済み", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await addToLibrary(share) }
                } label: {
                    if addingIDs.contains(share.id) {
                        ProgressView("追加中…")
                    } else {
                        Label("ライブラリに追加", systemImage: "plus")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(addingIDs.contains(share.id))
                .accessibilityIdentifier("authoring.addShared.\(share.id)")
            }
        }
        .padding(.vertical, 4)
    }

    private func addToLibrary(_ share: QuestionSetShare) async {
        guard !addingIDs.contains(share.id) else { return }
        addingIDs.insert(share.id)
        defer { addingIDs.remove(share.id) }
        do {
            try await service.addToLibrary(share)
        } catch {
            actionError = error.localizedDescription
            showsActionError = true
        }
    }
}

#Preview {
    NavigationStack { QuestionCreateView() }
}
