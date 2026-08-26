import SwiftUI

/// 未実装教材の表示定義。実装済みになった教材はここから削除する
enum UpcomingMaterial: String, CaseIterable, Identifiable {
    case eiken
    case mathematics
    case kanjiKentei
    case spi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eiken: return "英検対策"
        case .mathematics: return "数学"
        case .kanjiKentei: return "漢検"
        case .spi: return "SPI対策"
        }
    }

    var description: String {
        switch self {
        case .eiken: return "級別の英語力を強化"
        case .mathematics: return "計算と公式をトレーニング"
        case .kanjiKentei: return "読み書きと語彙を学習"
        case .spi: return "就職試験の基礎を対策"
        }
    }

    var systemImage: String {
        switch self {
        case .eiken: return "character.book.closed.fill"
        case .mathematics: return "function"
        case .kanjiKentei: return "textformat.characters"
        case .spi: return "person.text.rectangle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .eiken: return .purple
        case .mathematics: return .red
        case .kanjiKentei: return .brown
        case .spi: return .teal
        }
    }
}
