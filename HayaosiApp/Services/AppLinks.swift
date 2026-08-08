import Foundation

/// アプリ外へ案内するURLを、申請後に1か所だけ更新できるよう管理する
enum AppLinks {
    /// App ID確定後にApp Store URLを設定する。未申請中は共有文面へ無効なURLを載せないためnilにする
    static let appStoreURL: URL? = nil
}
