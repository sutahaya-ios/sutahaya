const { initializeApp } = require("firebase-admin/app");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();

const INVITE_COOLDOWN_MS = 10_000;
const ACCEPTING_LEASE_MS = 10_000;
const REGION = "asia-northeast1";
const INVITE_STATUSES = new Set(["pending", "accepting", "accepted", "cancelled"]);

function requireString(value, pattern) {
  return typeof value === "string" && pattern.test(value);
}

function fail(code, message, reason, extraDetails = {}) {
  throw new HttpsError(code, message, { reason, ...extraDetails });
}

function requireTimestamp(value, reason) {
  if (!(value instanceof Timestamp)) {
    fail("failed-precondition", "招待情報が正しくありません", reason);
  }
  return value;
}

exports.sendRoomInvite = onCall({ region: REGION }, async (request) => {
  const senderUID = request.auth?.uid;
  if (!senderUID) {
    fail("unauthenticated", "ログインが必要です", "unauthenticated");
  }

  const { friendUID, roomCode, roomInstanceID } = request.data ?? {};
  if (!requireString(friendUID, /^[^/]{1,128}$/)
      || !requireString(roomCode, /^[0-9]{4}$/)
      || !requireString(roomInstanceID, /^[A-Za-z0-9-]{1,128}$/)
      || friendUID === senderUID) {
    fail("invalid-argument", "招待情報が正しくありません", "invalid-invite");
  }

  const roomSnapshot = await getDatabase().ref(`rooms/${roomCode}`).get();
  if (!roomSnapshot.exists()) {
    fail("not-found", "ルームが見つかりません", "room-not-found");
  }
  const room = roomSnapshot.val();
  if (room.roomInstanceID !== roomInstanceID) {
    fail("failed-precondition", "ルームが更新されています", "stale-room");
  }
  if (room.hostID !== senderUID) {
    fail("permission-denied", "ホストだけが招待できます", "not-host");
  }
  if (room.status !== "waiting") {
    fail("failed-precondition", "待機中のルームだけ招待できます", "room-not-waiting");
  }

  const firestore = getFirestore();
  const senderProfileRef = firestore.doc(`users/${senderUID}`);
  const senderFriendRef = senderProfileRef.collection("friends").doc(friendUID);
  const recipientFriendRef = firestore.doc(`users/${friendUID}/friends/${senderUID}`);
  const [senderProfile, senderFriend, recipientFriend] = await firestore.getAll(
    senderProfileRef,
    senderFriendRef,
    recipientFriendRef
  );
  const nickname = senderProfile.data()?.nickname;
  if (typeof nickname !== "string" || nickname.length < 1 || nickname.length > 30) {
    fail("failed-precondition", "プロフィール情報が正しくありません", "invalid-profile");
  }
  if (!senderFriend.exists || !recipientFriend.exists) {
    fail("permission-denied", "フレンドだけを招待できます", "not-mutual-friends");
  }

  const inviteID = `${roomInstanceID}_${senderUID}`;
  const inviteRef = firestore.doc(`users/${friendUID}/invites/${inviteID}`);
  const generation = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(inviteRef);
    const now = Timestamp.now();
    let nextGeneration = 1;

    if (snapshot.exists) {
      const current = snapshot.data();
      if (current.roomInstanceID !== roomInstanceID
          || current.roomCode !== roomCode
          || current.fromUID !== senderUID
          || current.toUID !== friendUID
          || !Number.isInteger(current.generation)
          || current.generation < 1
          || !INVITE_STATUSES.has(current.status)) {
        fail("failed-precondition", "招待情報が正しくありません", "invalid-invite");
      }

      const sentAt = requireTimestamp(current.sentAt, "invalid-sent-at");
      const cooldownUntilMS = sentAt.toMillis() + INVITE_COOLDOWN_MS;
      if (now.toMillis() < cooldownUntilMS) {
        fail("resource-exhausted", "再招待の待機時間中です", "cooldown", {
          retryAfterMS: cooldownUntilMS,
        });
      }
      if (current.status === "accepting") {
        const acceptingAt = requireTimestamp(current.acceptingAt, "invalid-accepting-at");
        if (now.toMillis() < acceptingAt.toMillis() + ACCEPTING_LEASE_MS) {
          fail("aborted", "招待の参加処理中です", "claim-in-progress");
        }
      }
      nextGeneration = current.generation + 1;
    }

    transaction.set(inviteRef, {
      roomInstanceID,
      roomCode,
      fromUID: senderUID,
      toUID: friendUID,
      fromNickname: nickname,
      status: "pending",
      generation: nextGeneration,
      sentAt: FieldValue.serverTimestamp(),
    });
    return nextGeneration;
  });

  const savedInvite = await inviteRef.get();
  const sentAt = requireTimestamp(savedInvite.data()?.sentAt, "invalid-sent-at");
  return {
    inviteID,
    roomCode,
    roomInstanceID,
    fromUID: senderUID,
    toUID: friendUID,
    fromNickname: nickname,
    status: "pending",
    generation,
    sentAtMS: sentAt.toMillis(),
  };
});
