import Foundation

/// フレンド1人(Firestore users/{uid}/friends/{friendUid} のデコード結果)
/// 保存済みのフレンド情報。一覧表示時は users/{id} の最新プロフィールで一時的に更新される
struct Friend: Identifiable, Equatable {
    let id: String       // 相手のuid
    let nickname: String
    let friendCode: String
    var icon: String? = nil
    var bio: String? = nil
}
