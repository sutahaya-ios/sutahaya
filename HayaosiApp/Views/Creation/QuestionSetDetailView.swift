import SwiftUI

struct QuestionSetDetailView: View {
    let questionSetID: String
    let service: QuestionSetService

    @Environment(\.dismiss) private var dismiss
    @State private var showsShare = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var questionSet: QuestionSet? { service.questionSets[questionSetID] }

    var body: some View {
        Group {
            if let set = questionSet, set.status == .active {
                detailList(set)
            } else {
                ContentUnavailableView(
                    "この問題集は利用できません", systemImage: "books.vertical",
                    description: Text("削除されたか、利用が制限されています。")
                )
            }
        }
        .navigationTitle("問題集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsShare) {
            if let set = questionSet {
                QuestionSetShareView(questionSet: set, service: service)
            }
        }
        .confirmationDialog("この問題集を削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("問題集を削除", role: .destructive) {
                Task { await delete() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ライブラリから非表示になり、共有したフレンドも利用できなくなります。この画面から元に戻すことはできません。")
        }
        .task { await service.load() }
        .refreshable { await service.load() }
    }

    private func detailList(_ set: QuestionSet) -> some View {
        List {
            Section {
                Text(set.title).font(.title2.bold())
                Text("\(set.questions.count)問 · \(set.createdAt.formatted(date: .abbreviated, time: .omitted))作成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if set.creatorUID == service.uid {
                    Button {
                        showsShare = true
                    } label: {
                        Label("フレンドに共有", systemImage: "person.2.fill")
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("authoring.share")
                }
            }

            ForEach(Array(set.questions.enumerated()), id: \.element.id) { index, question in
                Section("問\(index + 1) · \(question.format.title)") {
                    Text(question.text)
                    if question.format == .multipleChoice {
                        ForEach(Array(question.choices.enumerated()), id: \.offset) { choiceIndex, choice in
                            Text("\(choiceIndex + 1). \(choice)")
                                .font(.subheadline)
                        }
                    }
                    LabeledContent("正解") {
                        Text(question.answers.joined(separator: " / "))
                            .multilineTextAlignment(.trailing)
                    }
                    if !question.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("解説").font(.caption).foregroundStyle(.secondary)
                            Text(question.explanation).font(.subheadline)
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if set.creatorUID == service.uid {
                Section {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        if isDeleting {
                            ProgressView("削除中…")
                        } else {
                            Label("問題集を削除", systemImage: "trash")
                        }
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("authoring.delete")
                } footer: {
                    Text("保存後は内容を編集できません。削除すると、共有したフレンドも利用できなくなります。")
                }
            }
        }
    }

    private func delete() async {
        guard !isDeleting, let set = questionSet else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await service.delete(set)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
