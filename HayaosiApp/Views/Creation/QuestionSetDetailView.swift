import SwiftUI

struct QuestionSetDetailView: View {
    let questionSetID: String
    let service: QuestionSetService

    @Environment(\.dismiss) private var dismiss
    @State private var showsShare = false
    @State private var isEditingQuestions = false
    @State private var editingQuestion: AuthoredQuestion?
    @State private var questionPendingDeletion: AuthoredQuestion?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var feedbackMessage: String?

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
        .toolbar {
            if let set = questionSet, set.status == .active, set.creatorUID == service.uid {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingQuestions ? "完了" : "編集") {
                        isEditingQuestions.toggle()
                        editingQuestion = nil
                        questionPendingDeletion = nil
                    }
                    .disabled(isUpdating || isDeleting)
                    .accessibilityIdentifier("authoring.edit.toggle")
                }
            }
        }
        .sheet(isPresented: $showsShare) {
            if let set = questionSet {
                QuestionSetShareView(questionSet: set, service: service)
            }
        }
        .sheet(item: $editingQuestion) { question in
            let isNew = questionSet?.questions.contains(where: { $0.id == question.id }) != true
            AuthoredQuestionEditorView(question: question, isNew: isNew) { saved in
                if isNew {
                    addQuestion(saved)
                } else {
                    saveEditedQuestion(saved)
                }
            }
        }
        .confirmationDialog(
            "この問題を削除しますか？",
            isPresented: Binding(
                get: { questionPendingDeletion != nil },
                set: { if !$0 { questionPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: questionPendingDeletion
        ) { question in
            Button("この問題を削除", role: .destructive) {
                Task { await deleteQuestion(question) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("問題集全体は削除されません。残りの問題はそのまま利用できます。")
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
                Text(set.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

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

            Section {
                NavigationLink {
                    AuthoredQuestionPracticeView(questionSet: set)
                } label: {
                    HStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.title3.bold())
                        Text("学習スタート")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("authoring.practice")
            }

            if let feedbackMessage {
                Section {
                    Label(feedbackMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("authoring.edit.feedback")
                }
            }

            ForEach(Array(set.questions.enumerated()), id: \.element.id) { index, question in
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Text(question.text)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isEditingQuestions, set.creatorUID == service.uid {
                            HStack(spacing: 10) {
                                Button {
                                    editingQuestion = question
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.body.bold())
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 38, height: 38)
                                        .background(Color(.tertiarySystemFill), in: Circle())
                                }
                                .accessibilityLabel("この問題を編集")
                                .accessibilityIdentifier("authoring.question.edit.\(index)")

                                Button(role: .destructive) {
                                    questionPendingDeletion = question
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.body.bold())
                                        .foregroundStyle(.red)
                                        .frame(width: 38, height: 38)
                                        .background(Color(.tertiarySystemFill), in: Circle())
                                }
                                .disabled(set.questions.count == 1)
                                .accessibilityLabel("この問題を削除")
                                .accessibilityIdentifier("authoring.question.delete.\(index)")
                            }
                            .buttonStyle(.borderless)
                            .disabled(isUpdating)
                        }
                    }
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

                    if isEditingQuestions, set.creatorUID == service.uid {
                        if set.questions.count == 1 {
                            Text("問題集には最低1問必要です。最後の問題は個別削除できません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("問\(index + 1)")
                        Text(formatBadge(question.format))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Color.accentColor)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }

            if isEditingQuestions, set.creatorUID == service.uid {
                Section {
                    Button {
                        guard set.questions.count < QuestionSetLimits.questions else { return }
                        editingQuestion = AuthoredQuestion(
                            format: .trueFalse,
                            text: "",
                            choices: ["○", "×"],
                            answers: ["○"]
                        )
                    } label: {
                        Label("問題を追加", systemImage: "plus.circle.fill")
                    }
                    .disabled(isUpdating || set.questions.count >= QuestionSetLimits.questions)
                    .accessibilityIdentifier("authoring.question.add")
                } footer: {
                    if set.questions.count >= QuestionSetLimits.questions {
                        Text("問題は最大\(QuestionSetLimits.questions)問まで追加できます。")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("authoring.edit.error")
                }
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
                    Text("問題集を削除すると、共有したフレンドも利用できなくなります。")
                }
            }
        }
    }

    private func formatBadge(_ format: AuthoredQuestionFormat) -> String {
        switch format {
        case .trueFalse: "○×"
        case .multipleChoice: "4択"
        case .shortAnswer: "記述"
        }
    }

    private func saveEditedQuestion(_ saved: AuthoredQuestion) {
        guard let set = questionSet,
              let index = set.questions.firstIndex(where: { $0.id == saved.id }) else { return }
        var questions = set.questions
        questions[index] = saved
        Task { await update(set, questions: questions, feedback: "保存しました") }
    }

    private func addQuestion(_ question: AuthoredQuestion) {
        guard let set = questionSet else { return }
        guard set.questions.count < QuestionSetLimits.questions else {
            errorMessage = "問題は最大\(QuestionSetLimits.questions)問まで追加できます。"
            return
        }
        var questions = set.questions
        questions.append(question)
        Task { await update(set, questions: questions, feedback: "問題を追加しました") }
    }

    private func deleteQuestion(_ question: AuthoredQuestion) async {
        guard let set = questionSet else { return }
        guard set.questions.count > 1 else {
            errorMessage = "問題集には最低1問必要です。"
            return
        }
        let questions = set.questions.filter { $0.id != question.id }
        await update(set, questions: questions, feedback: "問題を削除しました")
    }

    private func update(_ set: QuestionSet, questions: [AuthoredQuestion], feedback: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        feedbackMessage = nil
        defer { isUpdating = false }
        do {
            _ = try await service.updateQuestions(in: set, questions: questions)
            feedbackMessage = feedback
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if feedbackMessage == feedback { feedbackMessage = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
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

/// FirestoreのQuestionSetをそのまま使う一人用学習。短い記述を含む3形式に対応する。
private struct AuthoredQuestionPracticeView: View {
    let questionSet: QuestionSet

    @Environment(\.dismiss) private var dismiss
    @State private var questionIndex = 0
    @State private var correctCount = 0
    @State private var submittedAnswer: String?
    @State private var shortAnswer = ""
    @State private var isFinished = false

    private var question: AuthoredQuestion { questionSet.questions[questionIndex] }
    private var isCorrect: Bool {
        guard let submittedAnswer else { return false }
        return question.answers.contains { normalized($0) == normalized(submittedAnswer) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isFinished {
                    resultView
                } else {
                    ProgressView(value: Double(questionIndex + 1), total: Double(questionSet.questions.count))
                    Text("問\(questionIndex + 1) / \(questionSet.questions.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(question.text)
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                    answerControls

                    if submittedAnswer != nil {
                        feedback
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(questionSet.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var answerControls: some View {
        if question.format == .shortAnswer {
            TextField("答えを入力", text: $shortAnswer)
                .textFieldStyle(.roundedBorder)
                .disabled(submittedAnswer != nil)
                .submitLabel(.done)
                .onSubmit { submit(shortAnswer) }
            Button("回答する") { submit(shortAnswer) }
                .buttonStyle(.borderedProminent)
                .disabled(submittedAnswer != nil || normalized(shortAnswer).isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(spacing: 12) {
                ForEach(question.choices, id: \.self) { choice in
                    Button { submit(choice) } label: {
                        Text(choice)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(submittedAnswer != nil)
                }
            }
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isCorrect ? "正解" : "不正解", systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(isCorrect ? .green : .red)
            if !isCorrect {
                LabeledContent("正解") { Text(question.answers.joined(separator: " / ")) }
            }
            if !question.explanation.isEmpty {
                Text(question.explanation).font(.subheadline)
            }
            Button(questionIndex + 1 == questionSet.questions.count ? "結果を見る" : "次の問題") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var resultView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text("学習完了").font(.title.bold())
            Text("\(questionSet.questions.count)問中 \(correctCount)問正解")
                .font(.title2.bold())
            Button("もう一度") { restart() }
                .buttonStyle(.borderedProminent)
            Button("問題集に戻る") { dismiss() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func submit(_ answer: String) {
        guard submittedAnswer == nil, !normalized(answer).isEmpty else { return }
        submittedAnswer = answer
        if question.answers.contains(where: { normalized($0) == normalized(answer) }) {
            correctCount += 1
        }
    }

    private func advance() {
        if questionIndex + 1 == questionSet.questions.count {
            isFinished = true
        } else {
            questionIndex += 1
            submittedAnswer = nil
            shortAnswer = ""
        }
    }

    private func restart() {
        questionIndex = 0
        correctCount = 0
        submittedAnswer = nil
        shortAnswer = ""
        isFinished = false
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    }
}
