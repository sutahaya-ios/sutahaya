import SwiftUI

extension StudyCategory {
    var studyDescription: String {
        switch self {
        case .juniorHigh: return "基礎から積み上げる"
        case .highSchool: return "受験レベルまで対応"
        case .toeic: return "ビジネス英語に対応"
        case .spiVerbal: return "語彙と読解を鍛える"
        case .spiNonVerbal: return "推論と計算を鍛える"
        }
    }

    var studySystemImage: String {
        switch self {
        case .juniorHigh: return "books.vertical.fill"
        case .highSchool: return "graduationcap.fill"
        case .toeic: return "briefcase.fill"
        case .spiVerbal: return "text.book.closed.fill"
        case .spiNonVerbal: return "function"
        }
    }

    var studyAccentColor: Color {
        switch self {
        case .juniorHigh: return .blue
        case .highSchool: return .orange
        case .toeic: return .green
        case .spiVerbal: return .purple
        case .spiNonVerbal: return .pink
        }
    }

    var studyBackgroundColor: Color {
        studyAccentColor.opacity(0.12)
    }
}
