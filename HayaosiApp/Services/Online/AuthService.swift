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
        let doc = Firestore.firestore().collection("users").document(uid)
        let snapshot = try await doc.getDocument()

        if let data = snapshot.data(), let existingCode = data["friendCode"] as? String {
            friendCode = existingCode
            // ニックネームは端末側の設定を正として同期する
            if data["nickname"] as? String != nickname {
                try await doc.setData(["nickname": nickname], merge: true)
            }
            return
        }

        let code = try await generateUniqueFriendCode()
        try await doc.setData([
            "nickname": nickname,
            "friendCode": code,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
        friendCode = code
    }

    private func generateUniqueFriendCode() async throws -> String {
        let users = Firestore.firestore().collection("users")
        for _ in 0..<Self.codeAttempts {
            let code = String((0..<Self.codeLength).compactMap { _ in Self.codeAlphabet.randomElement() })
            let duplicated = try await users
                .whereField("friendCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            if duplicated.isEmpty { return code }
        }
        throw OnlineError.friendCodeGeneration
    }
}
