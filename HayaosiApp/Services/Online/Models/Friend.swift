import Foundation

/// フレンド1人(Firestore users/{uid}/friends/{friendUid} のデコード結果)
/// icon/bioはfirestore.rulesが書き込みを許可した後に値が入る(現時点では常にnil。要トキヤ氏対応)
struct Friend: Identifiable, Equatable {
    let id: String       // 相手のuid
    let nickname: String
    let friendCode: String
    var icon: String? = nil
    var bio: String? = nil
}
