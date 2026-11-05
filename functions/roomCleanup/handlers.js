const { getDatabase } = require("firebase-admin/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { STALE_ROOM_MS, MAX_ROOMS_PER_RUN, planRoomCleanup } = require("./core");

async function performCleanupOperation(operation, path, summary, perform) {
  try {
    return { succeeded: true, value: await perform() };
  } catch (error) {
    summary.failures += 1;
    console.error("room_cleanup_failed", {
      product: "RTDB",
      operation,
      path,
      errorCode: error?.code ?? "unknown",
    });
    return { succeeded: false };
  }
}

async function readCleanupInputs(database, nowEpochMs, summary) {
  const reads = [
    {
      operation: "query_closed_rooms",
      path: "rooms",
      query: database.ref("rooms").orderByChild("status")
        .equalTo("closed").limitToFirst(MAX_ROOMS_PER_RUN),
    },
    {
      operation: "query_stale_rooms",
      path: "rooms",
      query: database.ref("rooms").orderByChild("createdAt")
        .endAt(nowEpochMs - STALE_ROOM_MS).limitToFirst(MAX_ROOMS_PER_RUN),
    },
    { operation: "read_records", path: "roomCleanup", query: database.ref("roomCleanup") },
  ];
  const results = await Promise.all(reads.map(({ operation, path, query }) => (
    performCleanupOperation(operation, path, summary, () => query.get())
  )));
  // 読み取り失敗を「ルームなし」と扱うと観測記録を誤削除するため、次回へ持ち越す。
  if (results.some((result) => !result.succeeded)) return null;

  const [closedRooms, staleRooms, records] = results.map((result) => result.value.val() ?? {});
  summary.closedRoomsRead = Object.keys(closedRooms).length;
  summary.staleRoomsRead = Object.keys(staleRooms).length;
  summary.recordsRead = Object.keys(records).length;
  return { closedRooms, staleRooms, records, nowEpochMs };
}

async function writeCleanupRecord(database, code, value, summary) {
  const path = `roomCleanup/${code}`;
  const operation = value === null ? "remove_record" : "set_record";
  const result = await performCleanupOperation(operation, path, summary, () => (
    database.ref(path).set(value)
  ));
  if (result.succeeded) {
    summary[value === null ? "recordsRemoved" : "recordsSet"] += 1;
  }
}

async function deletePlannedRoom(database, target, initialValue, summary) {
  const path = `rooms/${target.code}`;
  let firstAttempt = true;
  const result = await performCleanupOperation("transaction_delete_room", path, summary, () => (
    database.ref(path).transaction((current) => {
      // 初回だけローカルキャッシュが空のことがある。競合後の再試行には補わない。
      if (current === null && firstAttempt) current = initialValue;
      firstAttempt = false;
      if (!current || (current.roomInstanceID ?? null) !== target.roomInstanceID
          || (target.requireClosed && current.status !== "closed")) {
        return;
      }
      return null;
    }, undefined, false)
  ));
  if (!result.succeeded) return;
  if (!result.value.committed) {
    summary.roomsSkipped += 1;
    return;
  }

  summary.roomsDeleted += 1;
  // ここだけ失敗しても、次回はclosedクエリから消えたルームの記録として回収される。
  await writeCleanupRecord(database, target.code, null, summary);
}

exports.cleanupStaleRooms = onSchedule({
  schedule: "every 15 minutes",
  region: "asia-northeast1",
  timeZone: "Asia/Tokyo",
}, async () => {
  const nowEpochMs = Date.now();
  const summary = {
    closedRoomsRead: 0,
    staleRoomsRead: 0,
    recordsRead: 0,
    recordsSet: 0,
    recordsRemoved: 0,
    roomsPlanned: 0,
    roomsDeleted: 0,
    roomsSkipped: 0,
    failures: 0,
  };
  try {
    const database = getDatabase();
    const inputs = await readCleanupInputs(database, nowEpochMs, summary);
    if (!inputs) return;
    const plan = planRoomCleanup(inputs);
    summary.roomsPlanned = plan.roomsToDelete.length;

    for (const code of plan.recordsToRemove) {
      await writeCleanupRecord(database, code, null, summary);
    }
    for (const [code, record] of Object.entries(plan.recordsToSet)) {
      await writeCleanupRecord(database, code, record, summary);
    }
    for (const target of plan.roomsToDelete) {
      const initialValue = target.requireClosed
        ? inputs.closedRooms[target.code]
        : inputs.staleRooms[target.code];
      await deletePlannedRoom(database, target, initialValue, summary);
    }
  } finally {
    console.info("room_cleanup_summary", summary);
  }
});
