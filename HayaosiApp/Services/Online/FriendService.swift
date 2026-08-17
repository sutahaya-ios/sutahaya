import Foundation
import Observation
import FirebaseFirestore

/// フレンド申請・相互フレンドリスト・ルーム招待の管理
@MainActor
@Observable
final class FriendService {
    static let shared = FriendService()

    private static let friendCodeLength = 6
    private static let friendCodeCharacters = CharacterSet(
        charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    )

    private(set) var friends: [Friend] = []
    private(set) var friendRequests: [FriendRequest] = []
    private(set) var invites: [RoomInvite] = []

    private var listeningUID: String?
    private var friendListener: ListenerRegistration?
    private var friendRequestListener: ListenerRegistration?
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

        friendRequestListener = user.collection("friendRequests").order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    if let error {
                        print("フレンド申請の取得に失敗: \(error)")
                        return
                    }
                    self?.friendRequests = snapshot?.documents.map { doc in
                        FriendRequest(
                            id: doc.documentID,
                            nickname: doc.data()["fromNickname"] as? String ?? "?",
                            friendCode: doc.data()["fromFriendCode"] as? String ?? ""
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
        friendRequestListener?.remove()
        inviteListener?.remove()
        friendListener = nil
        friendRequestListener = nil
        inviteListener = nil
        listeningUID = nil
        friends = []
        friendRequests = []
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

    /// フレンドコードで検索して相手へ承認待ちの申請を送る。
    func sendFriendRequest(code: String) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == Self.friendCodeLength,
              normalized.unicodeScalars.allSatisfy(Self.friendCodeCharacters.contains) else {
            throw OnlineError.friendNotFound
        }
        guard normalized != AuthService.shared.friendCode else { throw OnlineError.cannotAddSelf }
        let codeSnapshot = try await db.collection("friendCodes").document(normalized).getDocument()
        guard let friendUID = codeSnapshot.data()?["uid"] as? String,
              friendUID != myUID else {
            throw OnlineError.friendNotFound
        }
        let myFriendRef = db.collection("users").document(myUID)
            .collection("friends").document(friendUID)
        let reciprocalFriendRef = db.collection("users").document(friendUID)
            .collection("friends").document(myUID)
        async let myFriendSnapshot = myFriendRef.getDocument()
        async let reciprocalFriendSnapshot = reciprocalFriendRef.getDocument()
        let (myFriend, reciprocalFriend) = try await (myFriendSnapshot, reciprocalFriendSnapshot)
        if myFriend.exists, reciprocalFriend.exists {
            throw OnlineError.alreadyFriend
        }

        let incomingRef = db.collection("users").document(myUID)
            .collection("friendRequests").document(friendUID)
        if try await incomingRef.getDocument().exists {
            throw OnlineError.incomingFriendRequestExists
        }

        let outgoingRef = db.collection("users").document(friendUID)
            .collection("friendRequests").document(myUID)
        if try await outgoingRef.getDocument().exists {
            throw OnlineError.friendRequestAlreadySent
        }

        let myProfile = try await db.collection("users").document(myUID).getDocument()
        guard let myProfileData = myProfile.data(),
              let nickname = myProfileData["nickname"] as? String,
              let friendCode = myProfileData["friendCode"] as? String else {
            throw OnlineError.notSignedIn
        }
        try await outgoingRef.setData([
            "fromUID": myUID,
            "fromNickname": nickname,
            "fromFriendCode": friendCode,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    /// 申請を承認し、双方のフレンド文書を同じバッチで作る。
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let myProfileSnapshot = try await db.collection("users").document(myUID).getDocument()
        let senderProfileSnapshot = try await db.collection("users").document(request.id).getDocument()
        guard let myProfile = myProfileSnapshot.data(),
              let senderProfile = senderProfileSnapshot.data() else {
            throw OnlineError.friendNotFound
        }

        let batch = db.batch()
        let myFriendRef = db.collection("users").document(myUID)
            .collection("friends").document(request.id)
        let senderFriendRef = db.collection("users").document(request.id)
            .collection("friends").document(myUID)
        let requestRef = db.collection("users").document(myUID)
            .collection("friendRequests").document(request.id)
        batch.setData(friendDocument(from: senderProfile), forDocument: myFriendRef)
        batch.setData(friendDocument(from: myProfile), forDocument: senderFriendRef)
        batch.deleteDocument(requestRef)
        try await batch.commit()
    }

    func declineFriendRequest(_ request: FriendRequest) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        try await db.collection("users").document(myUID)
            .collection("friendRequests").document(request.id).delete()
    }

    func removeFriend(id: String) async {
        guard let myUID = AuthService.shared.uid else { return }
        do {
            let batch = db.batch()
            batch.deleteDocument(
                db.collection("users").document(myUID).collection("friends").document(id)
            )
            batch.deleteDocument(
                db.collection("users").document(id).collection("friends").document(myUID)
            )
            try await batch.commit()
        } catch {
            print("フレンドの削除に失敗: \(error)")
        }
    }

    private func friendDocument(from profile: [String: Any]) -> [String: Any] {
        [
            "nickname": profile["nickname"] as? String ?? "?",
            "friendCode": profile["friendCode"] as? String ?? "",
            "icon": profile["icon"] as? String ?? "",
            "bio": profile["bio"] as? String ?? "",
            "addedAt": FieldValue.serverTimestamp()
        ]
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
