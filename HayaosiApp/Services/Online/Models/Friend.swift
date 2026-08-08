import Foundation

/// フレンド1人(Firestore users/{uid}/friends/{friendUid} のデコード結果)
struct Friend: Identifiable, Equatable {
    let id: String       // 相手のuid
    let nickname: String
    let friendCode: String
}
