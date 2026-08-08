import Foundation

/// ルーム招待1件(Firestore users/{uid}/invites/{autoId} のデコード結果)
struct RoomInvite: Identifiable, Equatable {
    let id: String
    let roomCode: String
    let fromNickname: String
}
