/// SPIの問題文を、最初の改行で指示文と本文に分ける。
struct QuestionPrompt {
    let instruction: String?
    let body: String

    init(text: String) {
        if let newline = text.firstIndex(of: "\n") {
            instruction = String(text[..<newline])
            body = String(text[text.index(after: newline)...])
        } else {
            instruction = nil
            body = text
        }
    }
}
