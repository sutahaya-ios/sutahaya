import Foundation

/// ルーム招待1件(Firestore users/{recipientUID}/invites/{roomInstanceID}_{senderUID})。
/// Firestore上にdocumentが残っていても、pendingかつ30秒以内だけが新規招待として有効。
struct RoomInvite: Identifiable, Equatable {
    enum Status: String {
        case pending
        case accepting
        case accepted
        case cancelled
    }

    static let lifetime: TimeInterval = 30
    static let resendCooldown: TimeInterval = 10
    static let acceptingLease: TimeInterval = 10

    let id: String
    let roomCode: String
    let fromNickname: String
    let roomInstanceID: String
    let fromUID: String
    let toUID: String
    let status: Status
    let generation: Int
    let sentAt: Date
    let acceptClaimID: String?
    let acceptingAt: Date?

    init(
        id: String,
        roomCode: String,
        fromNickname: String,
        roomInstanceID: String = "preview-room",
        fromUID: String = "preview-sender",
        toUID: String = "preview-recipient",
        status: Status = .pending,
        generation: Int = 1,
        sentAt: Date = .now,
        acceptClaimID: String? = nil,
        acceptingAt: Date? = nil
    ) {
        self.id = id
        self.roomCode = roomCode
        self.fromNickname = fromNickname
        self.roomInstanceID = roomInstanceID
        self.fromUID = fromUID
        self.toUID = toUID
        self.status = status
        self.generation = generation
        self.sentAt = sentAt
        self.acceptClaimID = acceptClaimID
        self.acceptingAt = acceptingAt
    }

    /// 同じcanonical documentが再招待で更新されても、新しい通知として区別するキー。
    var notificationID: String { "\(id)#\(generation)" }

    var expiresAt: Date { sentAt.addingTimeInterval(Self.lifetime) }

    func isLogicallyExpired(at date: Date) -> Bool {
        date >= expiresAt
    }

    /// pending／acceptingは期限内だけ表示し、accepted／cancelledは新規通知として扱わない。
    func isVisibleInvitation(at date: Date) -> Bool {
        guard !isLogicallyExpired(at: date) else { return false }
        return status == .pending || status == .accepting
    }
}

/// Firestoreでclaim済みのgenerationとclaim ID。finalize／rollbackの両方で照合する。
struct RoomInviteClaim: Equatable {
    let inviteID: String
    let recipientUID: String
    let roomCode: String
    let roomInstanceID: String
    let generation: Int
    let claimID: String
}

enum InviteLifecycleError: LocalizedError, Equatable {
    case invalidInvite
    case cooldown(until: Date)
    case expired
    case claimInProgress
    case staleClaim
    case rollbackExpired

    var errorDescription: String? {
        switch self {
        case .invalidInvite:
            return "招待情報が正しくありません"
        case let .cooldown(until):
            let seconds = max(1, Int(ceil(until.timeIntervalSinceNow)))
            return "再招待はあと\(seconds)秒後にできます"
        case .expired:
            return "この招待は期限切れです"
        case .claimInProgress:
            return "この招待は参加処理中です"
        case .staleClaim:
            return "招待が更新されています。最新の招待を確認してください"
        case .rollbackExpired:
            return "招待期限を過ぎたため再開できません"
        }
    }
}
