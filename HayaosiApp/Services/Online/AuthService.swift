import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

enum ProfileInputPolicy {
    static let defaultNickname = "ゲスト"
    static let nicknameMaxLength = 30

    static func normalizedNickname(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultNickname }
        return String(trimmed.prefix(nicknameMaxLength))
    }
}

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
    private static let signInRetryDelayNanoseconds: UInt64 = 500_000_000
    private static let profileIconKey = "profileIcon"
    private static let profileBioKey = "profileBio"
    private static let bioMaxLength = 140

    private init() {}

    var nickname: String {
        ProfileInputPolicy.normalizedNickname(
            UserDefaults.standard.string(forKey: "nickname") ?? ProfileInputPolicy.defaultNickname
        )
    }

    private var profileIcon: String {
        UserDefaults.standard.string(forKey: Self.profileIconKey) ?? ""
    }

    private var profileBio: String {
        let value = UserDefaults.standard.string(forKey: Self.profileBioKey) ?? ""
        return String(value.prefix(Self.bioMaxLength))
    }

    /// RTDBなどFirebase Authenticationだけを必要とする処理向け。
    /// FirestoreのプロフィールやfriendCodes索引に障害があっても、認証済みuidは利用できるようにする。
    @discardableResult
    func ensureAuthenticated() async throws -> String {
        guard OnlineService.isConfigured else { throw OnlineError.notConfigured }
        let user = try await authenticatedUser()
        uid = user.uid
        return user.uid
    }

    /// サインイン済みならそのuidを返し、未サインインなら匿名サインインしてプロフィールを用意する
    @discardableResult
    func ensureSignedIn() async throws -> String {
        guard OnlineService.isConfigured else { throw OnlineError.notConfigured }
        if let uid, friendCode != nil { return uid }

        do {
            return try await signInAndEnsureProfile()
        } catch {
            logFirebaseError(context: "サインイン・プロフィール準備の初回試行", error: error)
        }

        try await Task.sleep(nanoseconds: Self.signInRetryDelayNanoseconds)

        do {
            return try await signInAndEnsureProfile()
        } catch {
            logFirebaseError(context: "サインイン・プロフィール準備の再試行", error: error)
            throw error
        }
    }

    private func signInAndEnsureProfile() async throws -> String {
        let user = try await authenticatedUser()
        try await ensureProfile(uid: user.uid)
        uid = user.uid
        return user.uid
    }

    private func authenticatedUser() async throws -> User {
        if let current = Auth.auth().currentUser {
            return current
        }
        return try await Auth.auth().signInAnonymously().user
    }

    func updateProfileIfSignedIn(nickname: String, icon: String, bio: String) async {
        guard let uid else { return }
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData([
                    "nickname": ProfileInputPolicy.normalizedNickname(nickname),
                    "icon": icon,
                    "bio": String(bio.prefix(Self.bioMaxLength))
                ], merge: true)
        } catch {
            logFirebaseError(context: "プロフィールの同期", error: error)
        }
    }

    private func ensureProfile(uid: String) async throws {
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid)
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await doc.getDocument()
        } catch {
            logFirebaseError(context: "プロフィール文書の取得", error: error)
            throw error
        }

        if let data = snapshot.data(), let existingCode = data["friendCode"] as? String {
            do {
                friendCode = try await ensureFriendCodeIndex(
                    uid: uid,
                    existingCode: existingCode,
                    userData: data,
                    userDocument: doc,
                    db: db
                )
            } catch {
                logFirebaseError(context: "フレンドコード索引の確認", error: error)
                throw error
            }
            return
        }

        do {
            friendCode = try await createProfile(uid: uid, userDocument: doc, db: db)
        } catch {
            logFirebaseError(context: "プロフィールの新規作成", error: error)
            throw error
        }
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
                "icon": profileIcon,
                "bio": profileBio,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: userDocument)
            batch.setData(["uid": uid], forDocument: codeDocument)

            do {
                try await batch.commit()
                return code
            } catch let commitError {
                logFirebaseError(context: "プロフィール作成バッチの書き込み", error: commitError)
                // 同時に同じコードが確保された場合だけ再試行し、通信エラー等は呼び出し元へ返す。
                do {
                    if try await codeDocument.getDocument().exists { continue }
                } catch {
                    logFirebaseError(context: "プロフィール作成失敗後の索引確認", error: error)
                }
                throw commitError
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
            // プロフィール表示値は端末側の設定を正として同期する。
            if needsProfileUpdate(userData) {
                try await userDocument.setData(currentProfileFields(), merge: true)
            }
            return existingCode
        }

        if !codeSnapshot.exists {
            let batch = db.batch()
            if needsProfileUpdate(userData) {
                batch.setData(currentProfileFields(), forDocument: userDocument, merge: true)
            }
            batch.setData(["uid": uid], forDocument: codeDocument)
            do {
                try await batch.commit()
                return existingCode
            } catch let commitError {
                logFirebaseError(context: "既存フレンドコード索引の作成", error: commitError)
                let latestIndex: DocumentSnapshot
                do {
                    latestIndex = try await codeDocument.getDocument()
                } catch {
                    logFirebaseError(context: "索引作成失敗後の再取得", error: error)
                    throw commitError
                }
                if latestIndex.data()?["uid"] as? String == uid {
                    return existingCode
                }
                if !latestIndex.exists { throw commitError }
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
                "friendCode": code,
                "icon": profileIcon,
                "bio": profileBio
            ], forDocument: userDocument, merge: true)
            batch.setData(["uid": uid], forDocument: codeDocument)
            do {
                try await batch.commit()
                return code
            } catch let commitError {
                logFirebaseError(context: "フレンドコード再発行バッチの書き込み", error: commitError)
                do {
                    if try await codeDocument.getDocument().exists { continue }
                } catch {
                    logFirebaseError(context: "再発行失敗後の索引確認", error: error)
                }
                throw commitError
            }
        }
        throw OnlineError.friendCodeGeneration
    }

    private func currentProfileFields() -> [String: Any] {
        [
            "nickname": nickname,
            "icon": profileIcon,
            "bio": profileBio
        ]
    }

    private func needsProfileUpdate(_ userData: [String: Any]) -> Bool {
        userData["nickname"] as? String != nickname
            || userData["icon"] as? String != profileIcon
            || userData["bio"] as? String != profileBio
    }

    private func makeFriendCode() -> String {
        String((0..<Self.codeLength).compactMap { _ in Self.codeAlphabet.randomElement() })
    }

    private func logFirebaseError(context: String, error: Error) {
        let nsError = error as NSError
        var details = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let firestoreCode = firestoreErrorName(for: nsError) {
            details.append("firestoreCode=\(firestoreCode)")
        }
        if nsError.domain == AuthErrors.domain {
            let authCode = nsError.userInfo[AuthErrors.userInfoNameKey] as? String
                ?? AuthErrorCode(rawValue: nsError.code).map(String.init(describing:))
            if let authCode {
                details.append("authCode=\(authCode)")
            }
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlyingDomain=\(underlyingError.domain)")
            details.append("underlyingCode=\(underlyingError.code)")
        }
        details.append("message=\(nsError.localizedDescription)")

        OnlineService.debugLog("[AuthService] \(context): \(details.joined(separator: ", "))")
    }

    private func firestoreErrorName(for error: NSError) -> String? {
        guard error.domain == FirestoreErrorDomain,
              let code = FirestoreErrorCode.Code(rawValue: error.code) else {
            return nil
        }

        switch code {
        case .OK: return "ok"
        case .cancelled: return "cancelled"
        case .unknown: return "unknown"
        case .invalidArgument: return "invalidArgument"
        case .deadlineExceeded: return "deadlineExceeded"
        case .notFound: return "notFound"
        case .alreadyExists: return "alreadyExists"
        case .permissionDenied: return "permissionDenied"
        case .resourceExhausted: return "resourceExhausted"
        case .failedPrecondition: return "failedPrecondition"
        case .aborted: return "aborted"
        case .outOfRange: return "outOfRange"
        case .unimplemented: return "unimplemented"
        case .internal: return "internal"
        case .unavailable: return "unavailable"
        case .dataLoss: return "dataLoss"
        case .unauthenticated: return "unauthenticated"
        @unknown default: return "unknown(\(code.rawValue))"
        }
    }
}
