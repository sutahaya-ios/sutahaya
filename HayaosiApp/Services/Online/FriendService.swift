import Foundation
import Observation
import FirebaseFirestore
import FirebaseFunctions

private struct SendRoomInviteRequest: Encodable {
    let friendUID: String
    let roomCode: String
    let roomInstanceID: String
}

private struct SendRoomInviteResponse: Decodable {
    let inviteID: String
    let roomCode: String
    let roomInstanceID: String
    let fromUID: String
    let toUID: String
    let fromNickname: String
    let status: String
    let generation: Int
    let sentAtMS: Double
}

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
    private(set) var sentFriendRequests: [SentFriendRequest] = []
    private(set) var invites: [RoomInvite] = []

    private var listeningUID: String?
    private var friendListener: ListenerRegistration?
    private var friendRequestListener: ListenerRegistration?
    private var sentFriendRequestListener: ListenerRegistration?
    private var inviteListener: ListenerRegistration?

    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private var cloudFunctions: Functions { Functions.functions(region: "asia-northeast1") }

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

        sentFriendRequestListener = user.collection("sentFriendRequests")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    if let error {
                        print("送信済みフレンド申請の取得に失敗: \(error)")
                        return
                    }
                    self?.sentFriendRequests = snapshot?.documents.map { doc in
                        SentFriendRequest(
                            id: doc.documentID,
                            nickname: doc.data()["toNickname"] as? String ?? "?",
                            friendCode: doc.data()["toFriendCode"] as? String ?? ""
                        )
                    } ?? []
                }
            }

        inviteListener = user.collection("invites").order(by: "sentAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    guard self?.listeningUID == uid else { return }
                    if let error {
                        print("招待の取得に失敗: \(error)")
                        return
                    }
                    self?.invites = snapshot?.documents.compactMap { doc in
                        Self.decodeInvite(document: doc, recipientUID: uid)
                    } ?? []
                }
            }
    }

    func stopListening() {
        friendListener?.remove()
        friendRequestListener?.remove()
        sentFriendRequestListener?.remove()
        inviteListener?.remove()
        friendListener = nil
        friendRequestListener = nil
        sentFriendRequestListener = nil
        inviteListener = nil
        listeningUID = nil
        friends = []
        friendRequests = []
        sentFriendRequests = []
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
        let myUserRef = db.collection("users").document(myUID)
        let recipientUserRef = db.collection("users").document(friendUID)
        let myFriendRef = myUserRef
            .collection("friends").document(friendUID)
        let reciprocalFriendRef = recipientUserRef
            .collection("friends").document(myUID)
        async let myFriendSnapshot = myFriendRef.getDocument()
        async let reciprocalFriendSnapshot = reciprocalFriendRef.getDocument()
        async let myProfileSnapshot = myUserRef.getDocument()
        async let recipientProfileSnapshot = recipientUserRef.getDocument()
        let (myFriend, reciprocalFriend, myProfile, recipientProfile) = try await (
            myFriendSnapshot,
            reciprocalFriendSnapshot,
            myProfileSnapshot,
            recipientProfileSnapshot
        )
        if myFriend.exists, reciprocalFriend.exists {
            throw OnlineError.alreadyFriend
        }

        let incomingRef = myUserRef
            .collection("friendRequests").document(friendUID)
        async let incomingSnapshot = incomingRef.getDocument()
        if try await incomingSnapshot.exists {
            throw OnlineError.incomingFriendRequestExists
        }

        let outgoingRef = recipientUserRef
            .collection("friendRequests").document(myUID)
        let sentRequestRef = myUserRef.collection("sentFriendRequests").document(friendUID)
        async let outgoingSnapshot = outgoingRef.getDocument()
        async let sentRequestSnapshot = sentRequestRef.getDocument()
        let (outgoingRequest, sentRequest) = try await (outgoingSnapshot, sentRequestSnapshot)
        if outgoingRequest.exists, sentRequest.exists {
            throw OnlineError.friendRequestAlreadySent
        }

        guard let myProfileData = myProfile.data(),
              let nickname = myProfileData["nickname"] as? String,
              let friendCode = myProfileData["friendCode"] as? String else {
            throw OnlineError.notSignedIn
        }
        guard let recipientProfileData = recipientProfile.data(),
              let recipientNickname = recipientProfileData["nickname"] as? String,
              let recipientFriendCode = recipientProfileData["friendCode"] as? String else {
            throw OnlineError.friendNotFound
        }
        let batch = db.batch()
        // 送信済み一覧の導入前に作られた片側だけの申請も、同じコードの再入力で補完する。
        // 既存文書は更新不可のルールなので、欠けている側だけを作成する。
        if !outgoingRequest.exists {
            batch.setData([
                "fromUID": myUID,
                "fromNickname": nickname,
                "fromFriendCode": friendCode,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: outgoingRef)
        }
        if !sentRequest.exists {
            batch.setData([
                "toUID": friendUID,
                "toNickname": recipientNickname,
                "toFriendCode": recipientFriendCode,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: sentRequestRef)
        }
        try await batch.commit()
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
        let sentRequestRef = db.collection("users").document(request.id)
            .collection("sentFriendRequests").document(myUID)
        batch.setData(friendDocument(from: senderProfile), forDocument: myFriendRef)
        batch.setData(friendDocument(from: myProfile), forDocument: senderFriendRef)
        batch.deleteDocument(requestRef)
        batch.deleteDocument(sentRequestRef)
        try await batch.commit()
    }

    func declineFriendRequest(_ request: FriendRequest) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let batch = db.batch()
        batch.deleteDocument(
            db.collection("users").document(myUID)
                .collection("friendRequests").document(request.id)
        )
        batch.deleteDocument(
            db.collection("users").document(request.id)
                .collection("sentFriendRequests").document(myUID)
        )
        try await batch.commit()
    }

    func removeFriend(id: String) async throws {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        let batch = db.batch()
        batch.deleteDocument(
            db.collection("users").document(myUID).collection("friends").document(id)
        )
        batch.deleteDocument(
            db.collection("users").document(id).collection("friends").document(myUID)
        )
        try await batch.commit()
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

    /// フレンドへ新規招待または再招待を送る。
    /// callable FunctionがRTDBのhost真正性を検証してからcanonical documentを更新する。
    @discardableResult
    func sendInvite(
        to friendUID: String,
        roomCode: String,
        roomInstanceID: String
    ) async throws -> RoomInvite {
        guard let myUID = AuthService.shared.uid else { throw OnlineError.notSignedIn }
        guard !friendUID.isEmpty,
              !roomCode.isEmpty,
              !roomInstanceID.isEmpty,
              !myUID.contains("/"),
              !roomInstanceID.contains("/") else {
            throw InviteLifecycleError.invalidInvite
        }

        do {
            let callable = cloudFunctions.httpsCallable(
                "sendRoomInvite",
                requestAs: SendRoomInviteRequest.self,
                responseAs: SendRoomInviteResponse.self
            )
            let response = try await callable.call(SendRoomInviteRequest(
                friendUID: friendUID,
                roomCode: roomCode,
                roomInstanceID: roomInstanceID
            ))
            guard response.inviteID == "\(roomInstanceID)_\(myUID)",
                  response.roomCode == roomCode,
                  response.roomInstanceID == roomInstanceID,
                  response.fromUID == myUID,
                  response.toUID == friendUID,
                  response.status == RoomInvite.Status.pending.rawValue,
                  response.generation >= 1,
                  (1...30).contains(response.fromNickname.count) else {
                throw InviteLifecycleError.invalidInvite
            }
            return RoomInvite(
                id: response.inviteID,
                roomCode: response.roomCode,
                fromNickname: response.fromNickname,
                roomInstanceID: response.roomInstanceID,
                fromUID: response.fromUID,
                toUID: response.toUID,
                status: .pending,
                generation: response.generation,
                sentAt: Date(timeIntervalSince1970: response.sentAtMS / 1_000)
            )
        } catch {
            if let lifecycleError = Self.inviteLifecycleError(from: error) {
                throw lifecycleError
            }
            throw error
        }
    }

    /// pending招待をrecipient本人がclaimする。既に同じclaimでacceptingならretryとして再利用する。
    func claimInvite(_ invite: RoomInvite) async throws -> RoomInviteClaim {
        guard let myUID = AuthService.shared.uid, myUID == invite.toUID else {
            throw OnlineError.notSignedIn
        }
        let inviteRef = db.collection("users").document(myUID)
            .collection("invites").document(invite.id)
        var lifecycleError: InviteLifecycleError?
        var claimedID: String?

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(inviteRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                guard let current = Self.decodeInvite(document: snapshot, recipientUID: myUID),
                      current.generation == invite.generation,
                      current.fromUID == invite.fromUID,
                      current.roomInstanceID == invite.roomInstanceID,
                      current.roomCode == invite.roomCode else {
                    lifecycleError = .staleClaim
                    errorPointer?.pointee = Self.transactionError(.staleClaim)
                    return nil
                }

                switch current.status {
                case .pending:
                    guard !current.isLogicallyExpired(at: .now) else {
                        lifecycleError = .expired
                        errorPointer?.pointee = Self.transactionError(.expired)
                        return nil
                    }
                    let claimID = UUID().uuidString.lowercased()
                    claimedID = claimID
                    transaction.updateData([
                        "status": RoomInvite.Status.accepting.rawValue,
                        "acceptClaimID": claimID,
                        "acceptingAt": FieldValue.serverTimestamp(),
                        "rolledBackClaimID": FieldValue.delete()
                    ], forDocument: inviteRef)
                    return claimID
                case .accepting:
                    guard let currentClaimID = current.acceptClaimID,
                          invite.acceptClaimID == currentClaimID else {
                        lifecycleError = .claimInProgress
                        errorPointer?.pointee = Self.transactionError(.claimInProgress)
                        return nil
                    }
                    claimedID = currentClaimID
                    return currentClaimID
                case .accepted, .cancelled:
                    lifecycleError = .staleClaim
                    errorPointer?.pointee = Self.transactionError(.staleClaim)
                    return nil
                }
            }
        } catch {
            if let lifecycleError { throw lifecycleError }
            throw error
        }

        guard let claimedID else { throw InviteLifecycleError.staleClaim }
        return RoomInviteClaim(
            inviteID: invite.id,
            recipientUID: myUID,
            roomCode: invite.roomCode,
            roomInstanceID: invite.roomInstanceID,
            generation: invite.generation,
            claimID: claimedID
        )
    }

    /// RTDB join成功後、同じgeneration・claimだけをacceptedへ確定する。
    func finalizeInvite(_ claim: RoomInviteClaim) async throws {
        try await updateClaim(claim, action: .finalize)
    }

    /// RTDB join失敗時、まだ30秒以内なら同じclaimだけをpendingへ戻す。
    func rollbackInvite(_ claim: RoomInviteClaim) async throws {
        try await updateClaim(claim, action: .rollback)
    }

    private enum ClaimAction {
        case finalize
        case rollback
    }

    private func updateClaim(_ claim: RoomInviteClaim, action: ClaimAction) async throws {
        guard let myUID = AuthService.shared.uid, myUID == claim.recipientUID else {
            throw OnlineError.notSignedIn
        }
        let inviteRef = db.collection("users").document(myUID)
            .collection("invites").document(claim.inviteID)
        var lifecycleError: InviteLifecycleError?

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(inviteRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                guard let current = Self.decodeInvite(document: snapshot, recipientUID: myUID),
                      current.status == .accepting,
                      current.generation == claim.generation,
                      current.acceptClaimID == claim.claimID,
                      current.roomInstanceID == claim.roomInstanceID,
                      current.roomCode == claim.roomCode else {
                    lifecycleError = .staleClaim
                    errorPointer?.pointee = Self.transactionError(.staleClaim)
                    return nil
                }

                switch action {
                case .finalize:
                    transaction.updateData([
                        "status": RoomInvite.Status.accepted.rawValue,
                        "acceptedAt": FieldValue.serverTimestamp()
                    ], forDocument: inviteRef)
                case .rollback:
                    guard !current.isLogicallyExpired(at: .now) else {
                        lifecycleError = .rollbackExpired
                        errorPointer?.pointee = Self.transactionError(.rollbackExpired)
                        return nil
                    }
                    transaction.updateData([
                        "status": RoomInvite.Status.pending.rawValue,
                        // Rulesが直前のresource.acceptClaimIDとの一致を検証するrollback proof。
                        "rolledBackClaimID": claim.claimID,
                        "acceptClaimID": FieldValue.delete(),
                        "acceptingAt": FieldValue.delete(),
                        "acceptedAt": FieldValue.delete()
                    ], forDocument: inviteRef)
                }
                return nil
            }
        } catch {
            if let lifecycleError { throw lifecycleError }
            throw error
        }
    }

    nonisolated private static func decodeInvite(
        document: DocumentSnapshot,
        recipientUID: String
    ) -> RoomInvite? {
        guard let data = document.data(),
              let roomInstanceID = data["roomInstanceID"] as? String,
              let roomCode = data["roomCode"] as? String,
              let fromUID = data["fromUID"] as? String,
              let toUID = data["toUID"] as? String,
              toUID == recipientUID,
              let fromNickname = data["fromNickname"] as? String,
              (1...30).contains(fromNickname.count),
              let statusRaw = data["status"] as? String,
              let status = RoomInvite.Status(rawValue: statusRaw),
              let generation = (data["generation"] as? NSNumber)?.intValue,
              generation >= 1,
              let sentAt = data["sentAt"] as? Timestamp else {
            return nil
        }
        guard document.documentID == "\(roomInstanceID)_\(fromUID)" else { return nil }
        return RoomInvite(
            id: document.documentID,
            roomCode: roomCode,
            fromNickname: fromNickname,
            roomInstanceID: roomInstanceID,
            fromUID: fromUID,
            toUID: toUID,
            status: status,
            generation: generation,
            sentAt: sentAt.dateValue(),
            acceptClaimID: data["acceptClaimID"] as? String,
            acceptingAt: (data["acceptingAt"] as? Timestamp)?.dateValue()
        )
    }

    nonisolated private static func inviteLifecycleError(from error: Error) -> InviteLifecycleError? {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain,
              let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let reason = details["reason"] as? String else { return nil }
        switch reason {
        case "cooldown":
            guard let retryAfterMS = details["retryAfterMS"] as? NSNumber else {
                return .invalidInvite
            }
            return .cooldown(until: Date(
                timeIntervalSince1970: retryAfterMS.doubleValue / 1_000
            ))
        case "claim-in-progress":
            return .claimInProgress
        case "invalid-invite", "invalid-profile":
            return .invalidInvite
        default:
            return nil
        }
    }

    nonisolated private static func transactionError(_ error: InviteLifecycleError) -> NSError {
        NSError(
            domain: "HayaosiApp.InviteLifecycle",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
}
