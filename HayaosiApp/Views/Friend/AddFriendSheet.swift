import SwiftUI

/// フレンドコード入力でフレンド申請を送るシート
struct AddFriendSheet: View {
    private static let codeLength = 6

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false
    @State private var didSendRequest = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if didSendRequest {
                    ContentUnavailableView {
                        Label("申請を送信しました", systemImage: "paperplane.fill")
                    } description: {
                        Text("相手が承認すると、お互いのフレンド一覧に表示されます")
                    } actions: {
                        Button("閉じる") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Form {
                        Section {
                            TextField("フレンドコード(6桁)", text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.title3.monospaced())
                        } footer: {
                            Text("友達のフレンドタブに表示されているコードを入力してください")
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                            }
                        }

                        Section {
                            Button(isWorking ? "申請中…" : "申請する") {
                                Task { await add() }
                            }
                            .disabled(code.count != Self.codeLength || isWorking)
                        }
                    }
                }
            }
            .navigationTitle(didSendRequest ? "申請完了" : "フレンド申請")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !didSendRequest {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await FriendService.shared.sendFriendRequest(code: code)
            didSendRequest = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddFriendSheet()
}
