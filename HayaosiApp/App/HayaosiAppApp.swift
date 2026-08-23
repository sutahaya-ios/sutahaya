import SwiftUI
import SwiftData

@main
struct HayaosiAppApp: App {
    init() {
        OnlineService.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task { await AdsService.shared.start() }
        }
        .modelContainer(for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self])
    }
}
