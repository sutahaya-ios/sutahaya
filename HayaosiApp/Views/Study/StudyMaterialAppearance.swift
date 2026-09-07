import SwiftUI

extension StudyCategory {
    var studyDescription: String {
        switch self {
        case .juniorHigh: return "基礎から積み上げる"
        case .highSchool: return "受験レベルまで対応"
        case .toeic: return "ビジネス英語に対応"
        }
    }

    var studySystemImage: String {
        switch self {
        case .juniorHigh: return "books.vertical.fill"
        case .highSchool: return "graduationcap.fill"
        case .toeic: return "briefcase.fill"
        }
    }

    var studyAccentColor: Color {
        switch self {
        case .juniorHigh: return .blue
        case .highSchool: return .orange
        case .toeic: return .green
        }
    }

    var studyBackgroundColor: Color {
        studyAccentColor.opacity(0.12)
    }
}
