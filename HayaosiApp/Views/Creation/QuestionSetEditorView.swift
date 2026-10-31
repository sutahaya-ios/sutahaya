import SwiftUI

struct QuestionSetEditorView: View {
    let service: QuestionSetService

    @Environment(\.dismiss) private var dismiss
    @State private var draft = QuestionSetDraft()
    @State private var editingQuestion: AuthoredQuestion?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：英語の小テスト対策", text: $draft.title)
                        .accessibilityIdentifier("authoring.set.title")
                } header: {
                    Text("問題集タイトル")
                } footer: {
                    Text("\(QuestionSetLimits.title)文字以内。保存後は内容を編集できません。")
                }

                Section {
                    ForEach(Array(draft.questions.enumerated()), id: \.element.id) { index, question in
                        Button {
                            editingQuestion = question
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("問\(index + 1) · \(question.format.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(question.text)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                        }
                        .accessibilityIdentifier("authoring.set.question.\(index)")
                    }
                    .onDelete { draft.questions.remove(atOffsets: $0) }

                    Button {
                        editingQuestion = AuthoredQuestion(format: .trueFalse, text: "", choices: ["○", "×"], answers: ["○"])
                    } label: {
                        Label("問題を追加", systemImage: "plus.circle.fill")
                    }
                    .disabled(draft.questions.count >= QuestionSetLimits.questions)
                    .accessibilityIdentifier("authoring.set.addQuestion")
                } header: {
                    Text("問題（\(draft.questions.count) / \(QuestionSetLimits.questions)問）")
                } footer: {
                    Text("保存前は、問題をタップして修正、左へスワイプして削除できます。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("authoring.set.error")
                    }
                }
                if isSaving {
                    Section { ProgressView("問題集を保存中…") }
                }
            }
            .disabled(isSaving)
            .navigationTitle("問題集を新規作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("authoring.set.save")
                }
            }
            .sheet(item: $editingQuestion) { question in
                AuthoredQuestionEditorView(
                    question: question,
                    isNew: !draft.questions.contains(where: { $0.id == question.id })
                ) { saved in
                    if let index = draft.questions.firstIndex(where: { $0.id == saved.id }) {
                        draft.questions[index] = saved
                    } else {
                        draft.questions.append(saved)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await service.create(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
