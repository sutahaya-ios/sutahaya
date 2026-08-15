import Foundation
import Observation
import FirebaseFirestore

/// フレンドリスト(users/{uid}/friends)とルーム招待(users/{uid}/invites)の管理
/// フレンドは片方向フォロー方式(自分が追加した相手が自分のリストに載る)
@MainActor
@Observable
final class FriendService {
    static let shared = FriendService()

    private static let friendCodeLength = 6
    private static let friendCodeCharacters = CharacterSet(
        charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    )

    private(set) var friends: [Friend] = []
    private(set) var invites: [RoomInvite] = []

    private var listeningUID: String?
    private var friendListener: ListenerRegistration?
    private var inviteListener: ListenerRegistration?

    private init() {}

    private var db: Firestore { Firestore.firestore() }

    func startListening(uid: String) {
        guard listeningUID != uid else { return }
        stopListening()
        listeningUID = uid
        let user = db.collection("users").document(uid)

        friendListener = user.collection("friends").order(by: "addedAt")
            .addSnapshotListener { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    if let error {
                        print("フレンドリストの取得に失敗: \(error)")
                        return
                    }
                    self?.friends = snapshot?.documents.map { doc in
                        Friend(
                            id: doc.documentID,
                            nickname: doc.data()["nickname"] as? String ?? "?",
                            friendCode: doc.data()["friendCode"] as? String ?? "",
                            icon: doc.data()["icon"] as? String,
                            bio: doc.data()["bio"] as? String
                        )
                    } ?? []
                }
            }

        inviteListener = user.collection("invites").order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    if let error {
                        print("招待の取得に失敗: \(error)")
                        return
                    }
                    self?.invites = snapshot?.documents.map { doc in
                        RoomInvite(
                            id: doc.documentID,
                            roomCode: doc.data()["roomCode"] as? String ?? "",
                            fromNickname: doc.data()["fromNickname"] as? String ?? "?"
                        )
                    } ?? []
                }
            }
    }

    func stopListening() {
        friendListener?.remove()
        inviteListener?.remove()
        friendListener = nil
        inviteListener = nil
        listeningUID = nil
        friends = []
        invites = []
    }

    /// フレンド一覧を開いた時に users/{friendUid} から最新プロフィールを取得する。
    /// 常時監視や friends サブコレクションへの書き戻しは行わず、読み取りは表示時の1回に限定する。
    func refreshFriendProfiles() async {
        guard let expectedUID = listeningUID, !friends.isEmpty else { return }
        let friendIDs = friends.map(\.id)
        var refreshedProfiles: [String: Friend] = [:]

        for friendID in friendIDs {
            do {
                let snapshot = try await db.collection("users").document(friendID).getDocument()
                guard let data = snapshot.data() else { continue }
                let storedFriend = friends.first { $0.id == friendID }
                refreshedProfiles[friendID] = Friend(
                    id: friendID,
                    nickname: data["nickname"] as? String ?? storedFriend?.nickname ?? "?",
                    friendCode: data["friendCode"] as? String ?? storedFriend?.friendCode ?? "",
                    icon: data["icon"] as? String,
                    bio: data["bio"] as? String
                )
            } catch {
                print("フレンドプロフィールの取得に失敗(\(friendID)): \(error)")
            }
        }

        // 取得中にサインイン先が変わった場合、古い結果を新しい一覧へ混ぜない。
        guard listeningUID == expectedUID else { return }
        friends = friends.map { refreshedProfiles[$0.id] ?? $0 }
    }

    /// フレンドコードで検索して自分のリストに追加する
    func addFriend(code: String) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == Self.friendCodeLength,
              normalized.unicodeScalars.allSatisfy(Self.friendCodeCharacters.contains) else {
            throw OnlineError.friendNotFound
        }
        guard normalized != AuthService.shared.friendCode else { throw OnlineError.cannotAddSelf }
        guard !friends.contains(where: { $0.friendCode == normalized }) else { throw OnlineError.alreadyFriend }

        let codeSnapshot = try await db.collection("friendCodes").document(normalized).getDocument()
        guard let friendUID = codeSnapshot.data()?["uid"] as? String,
              friendUID != myUID else {
            throw OnlineError.friendNotFound
        }
        let profile = try await db.collection("users").document(friendUID).getDocument()
        guard let profileData = profile.data() else { throw OnlineError.friendNotFound }

        try await db.collection("users").document(myUID)
            .collection("friends").document(friendUID)
            .setData([
                "nickname": profileData["nickname"] as? String ?? "?",
                "friendCode": normalized,
                "icon": profileData["icon"] as? String ?? "",
                "bio": profileData["bio"] as? String ?? "",
                "addedAt": FieldValue.serverTimestamp()
            ])
    }

    func removeFriend(id: String) async {
        guard let myUID = AuthService.shared.uid else { return }
        do {
            try await db.collection("users").document(myUID)
                .collection("friends").document(id).delete()
        } catch {
            print("フレンドの削除に失敗: \(error)")
        }
    }

    /// フレンドにルーム招待を送る(相手の invites に書き込む)
    func sendInvite(to friendUID: String, roomCode: String) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        try await db.collection("users").document(friendUID)
            .collection("invites")
            .addDocument(data: [
                "roomCode": roomCode,
                "fromUID": myUID,
                "fromNickname": AuthService.shared.nickname,
                "createdAt": FieldValue.serverTimestamp()
            ])
    }

    func deleteInvite(id: String) async {
        guard let myUID = AuthService.shared.uid else { return }
        do {
            try await db.collection("users").document(myUID)
                .collection("invites").document(id).delete()
        } catch {
            print("招待の削除に失敗: \(error)")
        }
    }
}
