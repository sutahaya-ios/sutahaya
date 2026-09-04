import SwiftUI
import SwiftData

@main
struct HayaosiAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        OnlineService.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    await SubscriptionService.shared.start()
                    await AdsService.shared.start()
                }
                .onChange(of: scenePhase) { _, newScenePhase in
                    guard newScenePhase == .active else { return }
                    Task { await SubscriptionService.shared.refreshEntitlements() }
                }
        }
        .modelContainer(
            for: [Question.self, AnswerRecord.self, ReviewItem.self, DailyStudyTime.self, BattleRecord.self]
        )
    }
}
