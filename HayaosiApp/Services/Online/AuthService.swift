import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// 匿名認証とユーザープロフィール(users/{uid})の管理(要件 §7.1)
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var uid: String?
    private(set) var friendCode: String?

    /// 紛らわしい文字(I/O/0/1)を除いたフレンドコード用文字集合
    private static let codeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let codeLength = 6
    private static let codeAttempts = 5

    private init() {}

    var nickname: String {
        UserDefaults.standard.string(forKey: "nickname") ?? "ゲスト"
    }

    /// サインイン済みならそのuidを返し、未サインインなら匿名サインインしてプロフィールを用意する
    @discardableResult
    func ensureSignedIn() async throws -> String {
        guard OnlineService.isConfigured else { throw OnlineError.notConfigured }
        if let uid, friendCode != nil { return uid }

        let user: User
        if let current = Auth.auth().currentUser {
            user = current
        } else {
            user = try await Auth.auth().signInAnonymously().user
        }
        try await ensureProfile(uid: user.uid)
        uid = user.uid
        return user.uid
    }

    func updateNicknameIfSignedIn(_ newNickname: String) async {
        guard let uid else { return }
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["nickname": newNickname], merge: true)
        } catch {
            print("ニックネームの同期に失敗: \(error)")
        }
    }

    private func ensureProfile(uid: String) async throws {
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid)
        let snapshot = try await doc.getDocument()

        if let data = snapshot.data(), let existingCode = data["friendCode"] as? String {
            friendCode = try await ensureFriendCodeIndex(
                uid: uid,
                existingCode: existingCode,
                userData: data,
                userDocument: doc,
                db: db
            )
            return
        }

        friendCode = try await createProfile(uid: uid, userDocument: doc, db: db)
    }

    /// 本格ルールでは users と friendCodes を同じバッチで作る必要がある。
    /// コード衝突時は索引の作成が失敗するため、別コードで再試行する。
    private func createProfile(
        uid: String,
        userDocument: DocumentReference,
        db: Firestore
    ) async throws -> String {
        for _ in 0..<Self.codeAttempts {
            let code = makeFriendCode()
            let codeDocument = db.collection("friendCodes").document(code)
            let codeSnapshot = try await codeDocument.getDocument()
            guard !codeSnapshot.exists else { continue }

            let batch = db.batch()
            batch.setData([
                "nickname": nickname,
                "friendCode": code,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: userDocument)
            batch.setData(["uid": uid], forDocument: codeDocument)

            do {
                try await batch.commit()
                return code
            } catch {
                // 同時に同じコードが確保された場合だけ再試行し、通信エラー等は呼び出し元へ返す。
                if try await codeDocument.getDocument().exists { continue }
                throw error
            }
        }
        throw OnlineError.friendCodeGeneration
    }

    /// 暫定ルール時代に作られた users/{uid} に friendCodes 索引を補う。
    /// 既に別ユーザーが同じコードを持つ異常系では、安全な新コードへ付け替える。
    private func ensureFriendCodeIndex(
        uid: String,
        existingCode: String,
        userData: [String: Any],
        userDocument: DocumentReference,
        db: Firestore
    ) async throws -> String {
        let codeDocument = db.collection("friendCodes").document(existingCode)
        let codeSnapshot = try await codeDocument.getDocument()
        let indexedUID = codeSnapshot.data()?["uid"] as? String

        if indexedUID == uid {
            // ニックネームは端末側の設定を正として同期する。
            if userData["nickname"] as? String != nickname {
                try await userDocument.setData(["nickname": nickname], merge: true)
            }
            return existingCode
        }

        if !codeSnapshot.exists {
            let batch = db.batch()
            if userData["nickname"] as? String != nickname {
                batch.setData(["nickname": nickname], forDocument: userDocument, merge: true)
            }
            batch.setData(["uid": uid], forDocument: codeDocument)
            do {
                try await batch.commit()
                return existingCode
            } catch {
                let latestIndex = try await codeDocument.getDocument()
                if latestIndex.data()?["uid"] as? String == uid {
                    return existingCode
                }
                if !latestIndex.exists { throw error }
            }
        }

        return try await reassignFriendCode(uid: uid, userDocument: userDocument, db: db)
    }

    private func reassignFriendCode(
        uid: String,
        userDocument: DocumentReference,
        db: Firestore
    ) async throws -> String {
        for _ in 0..<Self.codeAttempts {
            let code = makeFriendCode()
            let codeDocument = db.collection("friendCodes").document(code)
            let codeSnapshot = try await codeDocument.getDocument()
            guard !codeSnapshot.exists else { continue }

            let batch = db.batch()
            batch.setData([
                "nickname": nickname,
                "friendCode": code
            ], forDocument: userDocument, merge: true)
            batch.setData(["uid": uid], forDocument: codeDocument)
            do {
                try await batch.commit()
                return code
            } catch {
                if try await codeDocument.getDocument().exists { continue }
                throw error
            }
        }
        throw OnlineError.friendCodeGeneration
    }

    private func makeFriendCode() -> String {
        String((0..<Self.codeLength).compactMap { _ in Self.codeAlphabet.randomElement() })
    }
}
