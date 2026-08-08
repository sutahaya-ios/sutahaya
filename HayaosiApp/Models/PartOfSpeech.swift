import Foundation

/// 単語の品詞。JSONの `pos` にはこの表記だけを使う
/// (誤答は同じ品詞から作るため、表記がゆれると選択肢のグループが分かれる)
enum PartOfSpeech: String, Codable, CaseIterable, Identifiable {
    case verb = "動詞"
    case noun = "名詞"
    case adjective = "形容詞"

    var id: String { rawValue }
    var displayName: String { rawValue }
}
