import SwiftUI

struct QuestionSetShareView: View {
    let questionSet: QuestionSet
    let service: QuestionSetService

    @Environment(\.dismiss) private var dismiss
    @State private var friendService = FriendService.shared
    @State private var selectedFriendID: String?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showsSuccess = false
    @State private var sharedNickname = ""

    private var selectedFriend: Friend? {
        friendService.friends.first { $0.id == selectedFriendID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(questionSet.title).font(.headline)
                } footer: {
                    Text("共有するフレンドを1人選んでください。相手の作問タブに届きます。")
                }

                Section("フレンド") {
                    ForEach(friendService.friends) { friend in
                        Button {
                            selectedFriendID = friend.id
                        } label: {
                            HStack(spacing: 12) {
                                AvatarCircle(
                                    name: friend.nickname, icon: friend.icon ?? ProfileIcon.none,
                                    size: 40, color: AvatarCircle.stableColor(for: friend.id)
                                )
                                Text(friend.nickname).foregroundStyle(.primary)
                                Spacer()
                                if selectedFriendID == friend.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .accessibilityIdentifier("authoring.friend.\(friend.id)")
                    }
                    if friendService.friends.isEmpty {
                        Text("フレンドがまだいません。マイページでフレンドを登録すると共有できます。")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                if isSending {
                    Section { ProgressView("共有中…") }
                }
            }
            .disabled(isSending)
            .navigationTitle("フレンドに共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("共有") { Task { await share() } }
                        .disabled(selectedFriend == nil || isSending)
                        .accessibilityIdentifier("authoring.sendShare")
                }
            }
            .interactiveDismissDisabled(isSending)
            .alert("共有しました", isPresented: $showsSuccess) {
                Button("閉じる") { dismiss() }
            } message: {
                Text("\(sharedNickname)さんの作問タブに問題集が届きます。")
            }
            .task { await friendService.refreshFriendProfiles() }
        }
    }

    private func share() async {
        guard !isSending, let friend = selectedFriend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await service.share(questionSet, with: friend)
            sharedNickname = friend.nickname
            showsSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
