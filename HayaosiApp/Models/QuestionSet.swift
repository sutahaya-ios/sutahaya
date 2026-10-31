import Foundation

/// 作問データはFirestoreへ保存する値型。学習履歴のSwiftData schemaには加えない。
enum AuthoredQuestionFormat: String, Codable, CaseIterable, Identifiable {
    case trueFalse
    case multipleChoice
    case shortAnswer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trueFalse: "○×"
        case .multipleChoice: "4択"
        case .shortAnswer: "短い記述"
        }
    }
}

enum QuestionSetStatus: String, Codable {
    case active
    case blocked
    case deleted
}

enum QuestionSetLimits {
    static let questions = 20
    static let title = 80
    static let text = 2_000
    static let answer = 200
    static let explanation = 4_000
    static let answerCandidates = 5
}

struct QuestionSetValidationError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

struct AuthoredQuestion: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var format: AuthoredQuestionFormat
    var text: String
    var choices: [String]
    var answers: [String]
    var explanation: String = ""

    func validated() throws -> AuthoredQuestion {
        var question = self
        question.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        question.choices = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        question.answers = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        question.explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !id.isEmpty, !id.contains("/"), id.count <= 128 else {
            throw QuestionSetValidationError(message: "問題の識別子が正しくありません。")
        }
        guard !question.text.isEmpty, question.text.count <= QuestionSetLimits.text else {
            throw QuestionSetValidationError(message: "問題文を1〜\(QuestionSetLimits.text)文字で入力してください。")
        }
        guard question.explanation.count <= QuestionSetLimits.explanation else {
            throw QuestionSetValidationError(message: "解説は\(QuestionSetLimits.explanation)文字以内で入力してください。")
        }
        guard question.answers.allSatisfy({ !$0.isEmpty && $0.count <= QuestionSetLimits.answer }) else {
            throw QuestionSetValidationError(message: "正解は1候補につき1〜\(QuestionSetLimits.answer)文字で入力してください。")
        }
        switch format {
        case .trueFalse:
            guard question.choices == ["○", "×"], question.answers.count == 1,
                  question.choices.contains(question.answers[0]) else {
                throw QuestionSetValidationError(message: "○×問題の正解を○か×から選んでください。")
            }
        case .multipleChoice:
            guard question.choices.count == 4,
                  question.choices.allSatisfy({ !$0.isEmpty && $0.count <= QuestionSetLimits.answer }),
                  Set(question.choices).count == 4 else {
                throw QuestionSetValidationError(message: "異なる選択肢を4つ、各1〜\(QuestionSetLimits.answer)文字で入力してください。")
            }
            guard question.answers.count == 1, question.choices.contains(question.answers[0]) else {
                throw QuestionSetValidationError(message: "4つの選択肢から正解を1つ選んでください。")
            }
        case .shortAnswer:
            guard question.choices.isEmpty,
                  (1...QuestionSetLimits.answerCandidates).contains(question.answers.count),
                  Set(question.answers).count == question.answers.count else {
                throw QuestionSetValidationError(message: "記述問題の正解候補は、重複しない1〜\(QuestionSetLimits.answerCandidates)個を登録してください。")
            }
        }
        return question
    }
}

struct QuestionSet: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var creatorUID: String
    var createdAt: Date
    var questions: [AuthoredQuestion]
    var status: QuestionSetStatus = .active
    var schemaVersion: Int = 1
}

struct QuestionSetDraft: Equatable {
    // 保存失敗後の再試行でも同じIDを使い、問題集の二重作成を避ける。
    var id: String = UUID().uuidString
    var title: String = ""
    var questions: [AuthoredQuestion] = []

    func validated() throws -> QuestionSetDraft {
        var draft = self
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.contains("/"), id.count <= 128 else {
            throw QuestionSetValidationError(message: "問題集の識別子が正しくありません。")
        }
        guard !draft.title.isEmpty, draft.title.count <= QuestionSetLimits.title else {
            throw QuestionSetValidationError(message: "問題集タイトルを1〜\(QuestionSetLimits.title)文字で入力してください。")
        }
        guard (1...QuestionSetLimits.questions).contains(questions.count) else {
            throw QuestionSetValidationError(message: "問題集には1〜\(QuestionSetLimits.questions)問を登録してください。")
        }
        guard Set(questions.map(\.id)).count == questions.count else {
            throw QuestionSetValidationError(message: "同じ問題が重複しています。問題を追加し直してください。")
        }
        draft.questions = try questions.map { try $0.validated() }
        return draft
    }
}

struct QuestionSetShare: Equatable, Identifiable {
    var id: String { questionSetID }
    var questionSetID: String
    var fromUID: String
    var toUID: String
    var fromNickname: String
    var title: String
    var sentAt: Date
}
