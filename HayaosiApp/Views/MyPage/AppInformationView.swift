import SwiftUI

/// バージョン・法務文書・今後提供予定の機能をまとめたアプリ情報画面
struct AppInformationView: View {
    private static let privacyPolicyURLString = "https://saikyo-app-team.github.io/app-privacy/"
    private static let termsOfServiceURLString = "https://saikyo-app-team.github.io/app-privacy/terms.html"

    var body: some View {
        List {
            Section("アプリ") {
                LabeledContent("バージョン", value: version)
            }

            Section("リンク") {
                if let termsOfServiceURL = URL(string: Self.termsOfServiceURLString) {
                    Link(destination: termsOfServiceURL) {
                        Label("利用規約", systemImage: "doc.text.fill")
                    }
                }

                if let privacyPolicyURL = URL(string: Self.privacyPolicyURLString) {
                    Link(destination: privacyPolicyURL) {
                        Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                    }
                }
            }

            Section("今後の機能") {
                NavigationLink {
                    QuestionCreateView()
                } label: {
                    Label("作問(次回アップデート予定)", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationTitle("アプリ情報")
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        AppInformationView()
    }
}
