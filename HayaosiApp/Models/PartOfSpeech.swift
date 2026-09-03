import Foundation

/// 単語の品詞。JSONの `pos` にはこの表記だけを使う
/// (誤答は品詞を基準にしたグループから作るため、表記がゆれるとグループが分かれる)
enum PartOfSpeech: String, Codable, CaseIterable, Identifiable {
    case verb = "動詞"
    case noun = "名詞"
    case adjective = "形容詞"
    case adverb = "副詞"
    case pronoun = "代名詞"
    case conjunction = "接続詞"
    case preposition = "前置詞"
    case auxiliary = "助動詞"

    enum DistractorGroup: Hashable {
        case verb
        case noun
        case adjective
        case adverb
        case minorFunctionWords
    }

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// 少数の4品詞は訳の見た目が近いため、誤答候補だけを共通化する。
    /// 各品詞が単独で4語以上に増えたら、個別グループへ分離できる。
    var distractorGroup: DistractorGroup {
        switch self {
        case .verb:
            return .verb
        case .noun:
            return .noun
        case .adjective:
            return .adjective
        case .adverb:
            return .adverb
        case .pronoun, .conjunction, .preposition, .auxiliary:
            return .minorFunctionWords
        }
    }
}
