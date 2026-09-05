import Foundation

/// アプリ外へ案内するURLを、申請後に1か所だけ更新できるよう管理する
enum AppLinks {
    /// App Storeの商品ページ。ルーム招待の共有文面へ掲載する
    static let appStoreURL = URL(string: "https://apps.apple.com/jp/app/id6800718737")

    /// Appleの標準EULA。自動更新サブスクの購入画面から到達できる必要がある(審査ガイドライン3.1.2)
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 公開済みのプライバシーポリシー。上と同じ理由で購入画面に置く
    static let privacyPolicy = URL(string: "https://sutahaya-ios.github.io/app-privacy/")!
}
