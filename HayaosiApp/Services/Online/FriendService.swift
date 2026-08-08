import Foundation
import Observation
import FirebaseFirestore

/// フレンドリスト(users/{uid}/friends)とルーム招待(users/{uid}/invites)の管理
/// フレンドは片方向フォロー方式(自分が追加した相手が自分のリストに載る)
@MainActor
@Observable
final class FriendService {
    static let shared = FriendService()

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
                            friendCode: doc.data()["friendCode"] as? String ?? ""
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

    /// フレンドコードで検索して自分のリストに追加する
    func addFriend(code: String) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized != AuthService.shared.friendCode else { throw OnlineError.cannotAddSelf }
        guard !friends.contains(where: { $0.friendCode == normalized }) else { throw OnlineError.alreadyFriend }

        let result = try await db.collection("users")
            .whereField("friendCode", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments()
        guard let doc = result.documents.first, doc.documentID != myUID else {
            throw OnlineError.friendNotFound
        }

        try await db.collection("users").document(myUID)
            .collection("friends").document(doc.documentID)
            .setData([
                "nickname": doc.data()["nickname"] as? String ?? "?",
                "friendCode": normalized,
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
        try await db.collection("users").document(friendUID)
            .collection("invites")
            .addDocument(data: [
                "roomCode": roomCode,
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
