import SwiftUI

/// 未実装教材の表示定義。実装済みになった教材はここから削除する。
/// SPI非言語は枠組みだけ実装済みで、問題がそろうまで `StudyCategory.isSelectable` と対でここへ置く
enum UpcomingMaterial: String, CaseIterable, Identifiable {
    case eiken
    case mathematics
    case kanjiKentei
    case spiNonVerbal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eiken: return "英検対策"
        case .mathematics: return "数学"
        case .kanjiKentei: return "漢検"
        case .spiNonVerbal: return "SPI 非言語"
        }
    }

    var description: String {
        switch self {
        case .eiken: return "級別の英語力を強化"
        case .mathematics: return "計算と公式をトレーニング"
        case .kanjiKentei: return "読み書きと語彙を学習"
        case .spiNonVerbal: return "推論と計算を鍛える"
        }
    }

    var systemImage: String {
        switch self {
        case .eiken: return "character.book.closed.fill"
        case .mathematics: return "function"
        case .kanjiKentei: return "textformat.characters"
        case .spiNonVerbal: return "person.text.rectangle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .eiken: return .purple
        case .mathematics: return .red
        case .kanjiKentei: return .brown
        case .spiNonVerbal: return .teal
        }
    }
}
