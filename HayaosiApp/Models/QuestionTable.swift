import Foundation

/// SPIの資料解釈で使う表。画像を持たず、行列のまま配布してアプリ側で描く
struct QuestionTable: Codable, Equatable, Hashable {
    let caption: String
    let header: [String]
    let rows: [[String]]
}
