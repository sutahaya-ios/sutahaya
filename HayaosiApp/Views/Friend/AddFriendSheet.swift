import SwiftUI

/// フレンドコード入力でフレンドを追加するシート
struct AddFriendSheet: View {
    private static let codeLength = 6

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
                    Button(isWorking ? "追加中…" : "追加する") {
                        Task { await add() }
                    }
                    .disabled(code.count != Self.codeLength || isWorking)
                }
            }
            .navigationTitle("フレンドを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
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
            try await FriendService.shared.addFriend(code: code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddFriendSheet()
}
