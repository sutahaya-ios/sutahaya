import Foundation
import FirebaseCore

/// Firebaseの初期化とオンライン機能の利用可否判定
/// GoogleService-Info.plist が無くてもアプリ本体(一人練習)は動作させる
enum OnlineService {
    private(set) static var isConfigured = false

    /// Firebaseの詳細エラーは開発時だけ記録し、Release版の端末ログへ残さない。
    static func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    /// Realtime Database(通信対戦)が使えるか。plistにDATABASE_URLが必要
    static var isDatabaseAvailable: Bool {
        isConfigured && !(FirebaseApp.app()?.options.databaseURL ?? "").isEmpty
    }

    static func configureIfPossible() {
        guard FirebaseApp.app() == nil else {
            isConfigured = true
            return
        }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            debugLog("GoogleService-Info.plist が見つからないため、オンライン機能は無効(セットアップ手順は FIREBASE_SETUP.md)")
            return
        }
        FirebaseApp.configure(options: options)
        isConfigured = true
    }
}

/// オンライン機能共通のエラー
enum OnlineError: LocalizedError {
    case notConfigured
    case notSignedIn
    case friendCodeGeneration
    case friendNotFound
    case cannotAddSelf
    case alreadyFriend
    case friendRequestAlreadySent
    case incomingFriendRequestExists

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "オンライン機能が未設定です(FIREBASE_SETUP.md を参照)"
        case .notSignedIn: return "サインインできていません。通信環境を確認してください"
        case .friendCodeGeneration: return "フレンドコードの発行に失敗しました。もう一度お試しください"
        case .friendNotFound: return "このコードのユーザーが見つかりません"
        case .cannotAddSelf: return "自分のコードは追加できません"
        case .alreadyFriend: return "すでにフレンドに追加済みです"
        case .friendRequestAlreadySent: return "この相手には申請済みです"
        case .incomingFriendRequestExists: return "この相手から申請が届いています。フレンド画面で承認してください"
        }
    }
}
