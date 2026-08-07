import SwiftUI

/// ルーム作成:設定を決めてルームを発行し、待機ロビーへ(要件 §5.1.1・§9-3)
struct RoomCreateView: View {
    @AppStorage("nickname") private var nickname = "ゲスト"
    @State private var questionCount = QuizDefaults.questionCount
    @State private var timeLimit = QuizDefaults.timeLimit
    @State private var style = QuizDefaults.style
    @State private var session: OnlineBattleSession?
    @State private var isCreating = false
    @State private var showRoom = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                QuizStylePicker(style: $style)
            } header: {
                Text("対戦形式")
            } footer: {
                Text(style.detail)
            }

            Section("対戦設定") {
                Picker("ジャンル", selection: .constant(Genre.englishWord)) {
                    ForEach(Genre.allCases) { genre in
                        Text(genre.displayName).tag(genre)
                    }
                }
                Picker("問題数", selection: $questionCount) {
                    ForEach(QuizDefaults.questionCountOptions, id: \.self) { count in
                        Text("\(count)問").tag(count)
                    }
                }
                Picker("制限時間", selection: $timeLimit) {
                    ForEach(QuizDefaults.timeLimitOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))秒 / 問").tag(seconds)
                    }
                }
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("ルームを作成")
                    }
                }
                .disabled(isCreating)
            } footer: {
                Text("作成すると参加コードが発行されます。同じ部屋の友達も遠隔の友達も、コード入力で入室できます。")
            }
        }
        .navigationTitle("ルーム作成")
        .navigationDestination(isPresented: $showRoom) {
            if let session {
                OnlineRoomView(session: session)
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

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let uid = try await AuthService.shared.ensureSignedIn()
            let newSession = try OnlineBattleSession(myID: uid, nickname: nickname)
            try await newSession.createRoom(settings: .init(
                questionCount: questionCount,
                timeLimit: timeLimit,
                genre: .englishWord,
                style: style
            ))
            session = newSession
            showRoom = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RoomCreateView()
    }
}
