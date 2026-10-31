import SwiftUI

/// 保存前の問題を入力する。確定済みの問題集は編集しない。
struct AuthoredQuestionEditorView: View {
    let question: AuthoredQuestion
    let isNew: Bool
    let onSave: (AuthoredQuestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var format: AuthoredQuestionFormat
    @State private var text: String
    @State private var choices: [String]
    @State private var correctChoice: Int
    @State private var trueFalseAnswer: String
    @State private var answerCandidates: String
    @State private var explanation: String
    @State private var errorMessage: String?

    init(question: AuthoredQuestion, isNew: Bool, onSave: @escaping (AuthoredQuestion) -> Void) {
        self.question = question
        self.isNew = isNew
        self.onSave = onSave
        _format = State(initialValue: question.format)
        _text = State(initialValue: question.text)
        _choices = State(initialValue: question.format == .multipleChoice ? question.choices : Array(repeating: "", count: 4))
        _correctChoice = State(initialValue: question.choices.firstIndex(of: question.answers.first ?? "") ?? 0)
        _trueFalseAnswer = State(initialValue: question.format == .trueFalse ? question.answers.first ?? "○" : "○")
        _answerCandidates = State(initialValue: question.format == .shortAnswer ? question.answers.joined(separator: "\n") : "")
        _explanation = State(initialValue: question.explanation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("問題形式") {
                    Picker("形式", selection: $format) {
                        ForEach(AuthoredQuestionFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("authoring.question.format")
                }

                Section {
                    TextField("問題文を入力", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("authoring.question.text")
                } header: {
                    Text("問題文")
                } footer: {
                    Text("\(QuestionSetLimits.text)文字以内")
                }

                answerSection

                Section {
                    TextField("解説を入力（任意）", text: $explanation, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("authoring.question.explanation")
                } header: {
                    Text("解説（任意）")
                } footer: {
                    Text("\(QuestionSetLimits.explanation)文字以内")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("authoring.question.error")
                    }
                }
            }
            .navigationTitle(isNew ? "問題を追加" : "問題を修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "反映", action: save)
                        .accessibilityIdentifier("authoring.question.save")
                }
            }
        }
    }

    @ViewBuilder
    private var answerSection: some View {
        switch format {
        case .trueFalse:
            Section("正解") {
                Picker("正解", selection: $trueFalseAnswer) {
                    Text("○").tag("○")
                    Text("×").tag("×")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("authoring.question.trueFalseAnswer")
            }
        case .multipleChoice:
            Section {
                ForEach(0..<4, id: \.self) { index in
                    TextField("選択肢\(index + 1)", text: $choices[index], axis: .vertical)
                        .accessibilityIdentifier("authoring.question.choice.\(index)")
                }
                Picker("正解", selection: $correctChoice) {
                    ForEach(0..<4, id: \.self) { index in
                        Text("選択肢\(index + 1)").tag(index)
                    }
                }
                .accessibilityIdentifier("authoring.question.correctChoice")
            } header: {
                Text("4つの選択肢と正解")
            } footer: {
                Text("各\(QuestionSetLimits.answer)文字以内。同じ選択肢は登録できません。")
            }
        case .shortAnswer:
            Section {
                TextField("正解候補を1行に1つ入力", text: $answerCandidates, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("authoring.question.answers")
            } header: {
                Text("正解候補")
            } footer: {
                Text("改行で区切って1〜\(QuestionSetLimits.answerCandidates)個、各\(QuestionSetLimits.answer)文字以内。表記違いも登録できます。")
            }
        }
    }

    private func save() {
        let submittedChoices: [String]
        let submittedAnswers: [String]
        switch format {
        case .trueFalse:
            submittedChoices = ["○", "×"]
            submittedAnswers = [trueFalseAnswer]
        case .multipleChoice:
            submittedChoices = choices
            submittedAnswers = choices.indices.contains(correctChoice) ? [choices[correctChoice]] : []
        case .shortAnswer:
            submittedChoices = []
            submittedAnswers = answerCandidates.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        do {
            let validated = try AuthoredQuestion(
                id: question.id, format: format, text: text,
                choices: submittedChoices, answers: submittedAnswers, explanation: explanation
            ).validated()
            onSave(validated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
