import SwiftUI

/// Firebase未設定時にオンライン系タブへ表示する案内
struct OnlineSetupRequiredView: View {
    /// Realtime Database だけが未設定の場合は文言を変える
    var databaseOnly = false

    var body: some View {
        ContentUnavailableView {
            Label("オンライン機能は準備中", systemImage: "icloud.slash")
        } description: {
            if databaseOnly {
                Text("Realtime Database の設定が見つかりません。\nFirebaseコンソールでRealtime Databaseを作成し、GoogleService-Info.plist を入れ直してください。\n\n手順:プロジェクト内 FIREBASE_SETUP.md")
            } else {
                Text("Firebaseの設定ファイル(GoogleService-Info.plist)がまだ追加されていません。\n追加されるまで、一人練習と復習はオフラインで利用できます。\n\n手順:プロジェクト内 FIREBASE_SETUP.md")
            }
        }
    }
}
