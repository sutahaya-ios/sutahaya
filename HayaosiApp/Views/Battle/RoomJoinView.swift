import SwiftUI

/// ルーム参加:コードを入力して入室(要件 §5.1.1・§9-3)
struct RoomJoinView: View {
    private static let minCodeLength = 4

    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var code: String
    @State private var session: OnlineBattleSession?
    @State private var isJoining = false
    @State private var showRoom = false
    @State private var errorMessage: String?

    init(initialCode: String = "") {
        _code = State(initialValue: initialCode)
    }

    var body: some View {
        Form {
            Section("参加コード") {
                TextField("4〜6桁のコード", text: $code)
                    .keyboardType(.numberPad)
                    .font(.title2.monospaced())
            }

            Section {
                Button {
                    Task { await join() }
                } label: {
                    if isJoining {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("入室する")
                    }
                }
                .buttonStyle(SoundButtonStyle())
                .disabled(code.count < Self.minCodeLength || isJoining)
            } footer: {
                Text("ホストに教えてもらったコードを入力してください")
            }
        }
        .navigationTitle("ルーム参加")
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                BattleFlowView(session: session)
            }
        }
        .onChange(of: showRoom) { _, isShowing in
            if !isShowing {
                session?.leave()
                session = nil
            }
        }
        .alert("エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            let newSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            try await newSession.joinRoom(code: code)
            session = newSession
            showRoom = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RoomJoinView()
    }
}
