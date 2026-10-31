import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// 作問専用のFirestore経路。既存の問題DB・対戦・招待には書き込まない。
@MainActor
@Observable
final class QuestionSetService {
    private(set) var library: [QuestionSet] = []
    private(set) var libraryIDs: Set<String> = []
    private(set) var sharedSets: [QuestionSetShare] = []
    private(set) var questionSets: [String: QuestionSet] = [:]
    private(set) var uid: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var warningMessage: String?

    private var db: Firestore { Firestore.firestore() }
    // 更新中の結果が保存直後の表示を巻き戻さないようにする。
    private var revision = 0

    func load() async {
        guard !isLoading else { return }
        guard OnlineService.isConfigured else {
            errorMessage = "作問機能のオンライン接続が利用できません。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let currentUID = try await AuthService.shared.ensureSignedIn()
            if uid != currentUID {
                library = []
                libraryIDs = []
                sharedSets = []
                questionSets = [:]
                warningMessage = nil
                uid = currentUID
            }
            FriendService.shared.startListening(uid: currentUID)
            let expectedRevision = revision
            let user = db.collection("users").document(currentUID)
            // serverを明示し、未反映のローカル書込みを保存済みとして扱わない。
            async let librarySnapshot = user.collection("library").getDocuments(source: .server)
            async let inboxSnapshot = user.collection("sharedQuestionSets").getDocuments(source: .server)
            let (saved, inbox) = try await (librarySnapshot, inboxSnapshot)
            var unavailableCount = 0
            let shares = inbox.documents.compactMap { document -> QuestionSetShare? in
                do { return try Self.decodeShare(document, recipientUID: currentUID) }
                catch {
                    unavailableCount += 1
                    _ = Self.report(error, operation: "decode", path: "users/{uid}/sharedQuestionSets/{id}")
                    return nil
                }
            }
            let ids = Set(saved.documents.map(\.documentID))
            let allIDs = ids.union(shares.map(\.questionSetID))
            var sets: [String: QuestionSet] = [:]
            for id in allIDs.sorted() {
                let snapshot = try await db.collection("questionSets").document(id).getDocument(source: .server)
                guard snapshot.exists else {
                    unavailableCount += 1
                    continue
                }
                // 不正な共有1件が、正常な自作問題や他の共有の読み込みを妨げないようにする。
                do { sets[id] = try Self.decodeSet(snapshot) }
                catch {
                    unavailableCount += 1
                    _ = Self.report(error, operation: "decode", path: "questionSets/{id}")
                }
            }
            guard Auth.auth().currentUser?.uid == currentUID, uid == currentUID,
                  revision == expectedRevision else { return }
            libraryIDs = ids
            sharedSets = shares.sorted { $0.sentAt > $1.sentAt }
            questionSets = sets
            rebuildLibrary()
            warningMessage = unavailableCount > 0
                ? "\(unavailableCount)件のデータを読み取れませんでした。他の問題集は利用できます。"
                : nil
            errorMessage = nil
        } catch {
            errorMessage = Self.report(error, operation: "read", path: "users/{uid}/library, sharedQuestionSets → questionSets/{id}")
        }
    }

    /// 固定したdraft.idで再試行。問題集と作成者の参照を同じtransactionで確定する。
    func create(_ draft: QuestionSetDraft) async throws -> QuestionSet {
        let draft = try draft.validated()
        let currentUID = try requireUID()
        let setRef = db.collection("questionSets").document(draft.id)
        let libraryRef = db.collection("users").document(currentUID).collection("library").document(draft.id)
        let payload: [String: Any] = [
            "title": draft.title, "creatorUID": currentUID,
            "createdAt": FieldValue.serverTimestamp(),
            "questions": draft.questions.map(Self.questionData),
            "status": QuestionSetStatus.active.rawValue, "schemaVersion": 1
        ]
        do {
            let existingDate = try await transaction { transaction in
                let existing = try transaction.getDocument(setRef)
                let library = try transaction.getDocument(libraryRef)
                if existing.exists {
                    let set = try Self.decodeSet(existing)
                    guard set.creatorUID == currentUID, set.status == .active,
                          set.title == draft.title, set.questions == draft.questions else {
                        throw QuestionSetServiceError.conflictingDraft
                    }
                } else {
                    transaction.setData(payload, forDocument: setRef)
                }
                if !library.exists {
                    transaction.setData([
                        "questionSetID": draft.id, "addedAt": FieldValue.serverTimestamp()
                    ], forDocument: libraryRef)
                }
                return existing.data()?["createdAt"] as? Timestamp
            }
            guard isCurrent(currentUID) else { throw QuestionSetServiceError.accountChanged }
            let set = QuestionSet(
                id: draft.id, title: draft.title, creatorUID: currentUID,
                createdAt: (existingDate as? Timestamp)?.dateValue() ?? .now,
                questions: draft.questions
            )
            revision += 1
            questionSets[set.id] = set
            libraryIDs.insert(set.id)
            rebuildLibrary()
            errorMessage = nil
            return set
        } catch {
            throw userError(error, operation: "transaction create", path: "questionSets/{id} + users/{uid}/library/{id}")
        }
    }

    func share(_ set: QuestionSet, with friend: Friend) async throws {
        let currentUID = try requireUID()
        guard set.creatorUID == currentUID, friend.id != currentUID else {
            throw QuestionSetServiceError.notCreator
        }
        let setRef = db.collection("questionSets").document(set.id)
        let shareRef = db.collection("users").document(friend.id).collection("sharedQuestionSets").document(set.id)
        let profileRef = db.collection("users").document(currentUID)
        do {
            _ = try await transaction { transaction in
                let current = try Self.decodeSet(transaction.getDocument(setRef))
                let existing = try transaction.getDocument(shareRef)
                let profile = try transaction.getDocument(profileRef)
                guard current.status == .active, current.creatorUID == currentUID else {
                    throw QuestionSetServiceError.unavailable
                }
                // 同じ相手への再送は既存の受信項目を維持する。
                if existing.exists { return nil }
                guard let nickname = profile.data()?["nickname"] as? String else {
                    throw QuestionSetServiceError.invalidData
                }
                transaction.setData([
                    "questionSetID": set.id, "fromUID": currentUID, "toUID": friend.id,
                    "fromNickname": nickname, "title": current.title,
                    "sentAt": FieldValue.serverTimestamp()
                ], forDocument: shareRef)
                return nil
            }
            guard isCurrent(currentUID) else { throw QuestionSetServiceError.accountChanged }
        } catch {
            throw userError(error, operation: "transaction share", path: "users/{recipient}/sharedQuestionSets/{id}")
        }
    }

    func addToLibrary(_ share: QuestionSetShare) async throws {
        let currentUID = try requireUID()
        guard share.toUID == currentUID else { throw QuestionSetServiceError.accountChanged }
        let setRef = db.collection("questionSets").document(share.questionSetID)
        let user = db.collection("users").document(currentUID)
        let shareRef = user.collection("sharedQuestionSets").document(share.questionSetID)
        let libraryRef = user.collection("library").document(share.questionSetID)
        do {
            let result = try await transaction { transaction in
                let current = try Self.decodeSet(transaction.getDocument(setRef))
                let incoming = try Self.decodeShare(transaction.getDocument(shareRef), recipientUID: currentUID)
                let existing = try transaction.getDocument(libraryRef)
                guard current.status == .active, incoming.fromUID == current.creatorUID else {
                    throw QuestionSetServiceError.unavailable
                }
                if !existing.exists {
                    transaction.setData([
                        "questionSetID": current.id, "addedAt": FieldValue.serverTimestamp()
                    ], forDocument: libraryRef)
                }
                return current
            }
            guard isCurrent(currentUID) else { throw QuestionSetServiceError.accountChanged }
            guard let set = result as? QuestionSet else { throw QuestionSetServiceError.invalidData }
            revision += 1
            questionSets[set.id] = set
            libraryIDs.insert(set.id)
            rebuildLibrary()
        } catch {
            throw userError(error, operation: "transaction add", path: "users/{uid}/library/{id}")
        }
    }

    func delete(_ set: QuestionSet) async throws {
        let currentUID = try requireUID()
        guard set.creatorUID == currentUID else { throw QuestionSetServiceError.notCreator }
        let setRef = db.collection("questionSets").document(set.id)
        do {
            _ = try await transaction { transaction in
                let current = try Self.decodeSet(transaction.getDocument(setRef))
                guard current.creatorUID == currentUID else { throw QuestionSetServiceError.notCreator }
                if current.status == .deleted { return nil }
                guard current.status == .active else { throw QuestionSetServiceError.unavailable }
                transaction.updateData(["status": QuestionSetStatus.deleted.rawValue], forDocument: setRef)
                return nil
            }
            guard isCurrent(currentUID) else { throw QuestionSetServiceError.accountChanged }
            revision += 1
            var deleted = set
            deleted.status = .deleted
            questionSets[set.id] = deleted
            rebuildLibrary()
        } catch {
            throw userError(error, operation: "transaction soft-delete", path: "questionSets/{id}")
        }
    }

    private func requireUID() throws -> String {
        guard OnlineService.isConfigured, let uid, isCurrent(uid) else {
            throw QuestionSetServiceError.accountChanged
        }
        return uid
    }

    private func isCurrent(_ expectedUID: String) -> Bool {
        uid == expectedUID && Auth.auth().currentUser?.uid == expectedUID
    }

    private func rebuildLibrary() {
        library = libraryIDs.compactMap { questionSets[$0] }
            .filter { $0.status == .active }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func transaction(_ body: @escaping (Transaction) throws -> Any?) async throws -> Any? {
        try await db.runTransaction { transaction, errorPointer in
            do { return try body(transaction) }
            catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    nonisolated private static func questionData(_ question: AuthoredQuestion) -> [String: Any] {
        ["id": question.id, "format": question.format.rawValue, "text": question.text,
         "choices": question.choices, "answers": question.answers, "explanation": question.explanation]
    }

    nonisolated private static func decodeSet(_ snapshot: DocumentSnapshot) throws -> QuestionSet {
        guard var data = snapshot.data() else { throw QuestionSetServiceError.unavailable }
        data["id"] = snapshot.documentID
        let set = try Firestore.Decoder().decode(QuestionSet.self, from: data)
        guard set.schemaVersion == 1, !set.creatorUID.isEmpty else { throw QuestionSetServiceError.invalidData }
        _ = try QuestionSetDraft(id: set.id, title: set.title, questions: set.questions).validated()
        return set
    }

    nonisolated private static func decodeShare(_ snapshot: DocumentSnapshot, recipientUID: String) throws -> QuestionSetShare {
        guard let data = snapshot.data(),
              data["questionSetID"] as? String == snapshot.documentID,
              data["toUID"] as? String == recipientUID,
              let fromUID = data["fromUID"] as? String,
              let fromNickname = data["fromNickname"] as? String,
              let title = data["title"] as? String,
              let sentAt = data["sentAt"] as? Timestamp else {
            throw QuestionSetServiceError.invalidData
        }
        return QuestionSetShare(
            questionSetID: snapshot.documentID, fromUID: fromUID, toUID: recipientUID,
            fromNickname: fromNickname, title: title, sentAt: sentAt.dateValue()
        )
    }

    private func userError(_ error: Error, operation: String, path: String) -> Error {
        QuestionSetServiceError.requestFailed(Self.report(error, operation: operation, path: path))
    }

    nonisolated private static func report(_ error: Error, operation: String, path: String) -> String {
        let nsError = error as NSError
        OnlineService.debugLog("[QuestionSet] product=Firestore operation=\(operation) path=\(path) domain=\(nsError.domain) code=\(nsError.code)")
        if let error = error as? QuestionSetServiceError { return error.localizedDescription }
        if let error = error as? QuestionSetValidationError { return error.localizedDescription }
        if nsError.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: nsError.code) {
            case .permissionDenied:
                return "この操作が許可されませんでした。フレンド関係や問題集の状態を確認して、もう一度お試しください。"
            case .unavailable, .deadlineExceeded:
                return "通信できませんでした。接続を確認して、もう一度お試しください。同じ操作を繰り返しても重複しません。"
            default: break
            }
        }
        return "処理を完了できませんでした。接続を確認して、もう一度お試しください。"
    }
}

private enum QuestionSetServiceError: LocalizedError {
    case accountChanged, notCreator, unavailable, conflictingDraft, invalidData
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .accountChanged: "接続状態が変わりました。作問画面を更新してから、もう一度お試しください。"
        case .notCreator: "この操作は問題集の作成者だけが行えます。"
        case .unavailable: "この問題集は削除されたか、現在利用できません。"
        case .conflictingDraft: "この問題集はすでに保存されています。画面を閉じてライブラリを更新してください。"
        case .invalidData: "問題集のデータを読み取れませんでした。アプリを更新してお試しください。"
        case .requestFailed(let message): message
        }
    }
}
