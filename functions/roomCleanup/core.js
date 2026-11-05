const CLOSED_GRACE_MS = 60 * 60 * 1000;
const STALE_ROOM_MS = 24 * 60 * 60 * 1000;
const MAX_ROOMS_PER_RUN = 500;

function planRoomCleanup({ closedRooms, staleRooms, records, nowEpochMs }) {
  const closedEntries = Object.entries(closedRooms ?? {});
  const observedRecords = records ?? {};
  const recordsToSet = {};
  const recordsToRemove = [];
  const roomsToDelete = new Map();

  for (const [code, room] of closedEntries) {
    if (room?.status !== "closed") continue;
    const roomInstanceID = room.roomInstanceID ?? null;
    const record = observedRecords[code];
    if (!record || (record.roomInstanceID ?? null) !== roomInstanceID
        || !Number.isFinite(record.firstSeenClosedAtEpochMs)) {
      recordsToSet[code] = { roomInstanceID, firstSeenClosedAtEpochMs: nowEpochMs };
      continue;
    }
    if (nowEpochMs - record.firstSeenClosedAtEpochMs >= CLOSED_GRACE_MS) {
      roomsToDelete.set(code, { code, roomInstanceID, requireClosed: true });
    }
  }

  // 上限に達したクエリでは、結果にないルームが復帰・消失したとは判断できない。
  if (closedEntries.length < MAX_ROOMS_PER_RUN) {
    for (const code of Object.keys(observedRecords)) {
      if (closedRooms?.[code]?.status !== "closed") recordsToRemove.push(code);
      // 同じコードの別ルームがclosedなら、上のrecordsToSetで古い記録を置き換える。
    }
  }

  for (const [code, room] of Object.entries(staleRooms ?? {})) {
    if (!Number.isFinite(room?.createdAt) || nowEpochMs - room.createdAt < STALE_ROOM_MS) {
      continue;
    }
    // 両クエリに含まれる場合も一度だけ削除し、24時間の条件を優先する。
    roomsToDelete.set(code, {
      code,
      roomInstanceID: room.roomInstanceID ?? null,
      requireClosed: false,
    });
  }

  return {
    recordsToSet,
    recordsToRemove,
    roomsToDelete: Array.from(roomsToDelete.values()).slice(0, MAX_ROOMS_PER_RUN),
  };
}

module.exports = { CLOSED_GRACE_MS, STALE_ROOM_MS, MAX_ROOMS_PER_RUN, planRoomCleanup };
