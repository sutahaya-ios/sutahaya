const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  CLOSED_GRACE_MS,
  STALE_ROOM_MS,
  MAX_ROOMS_PER_RUN,
  planRoomCleanup,
} = require("../functions/roomCleanup/core");

const NOW_EPOCH_MS = STALE_ROOM_MS * 2;
const ROOM_CODE = "0123";
const ROOM_INSTANCE_ID = "room-original";

function plan(overrides = {}) {
  return planRoomCleanup({
    closedRooms: {},
    staleRooms: {},
    records: {},
    nowEpochMs: NOW_EPOCH_MS,
    ...overrides,
  });
}

function closedRoom(roomInstanceID = ROOM_INSTANCE_ID) {
  return { roomInstanceID, status: "closed", createdAt: NOW_EPOCH_MS };
}

function record(firstSeenClosedAtEpochMs, roomInstanceID = ROOM_INSTANCE_ID) {
  return { roomInstanceID, firstSeenClosedAtEpochMs };
}

describe("フレンドルームの掃除計画", () => {
  it("初めて観測したclosedは記録だけを作る", () => {
    assert.deepEqual(plan({ closedRooms: { [ROOM_CODE]: closedRoom() } }), {
      recordsToSet: { [ROOM_CODE]: record(NOW_EPOCH_MS) },
      recordsToRemove: [],
      roomsToDelete: [],
    });
  });

  it("closedの観測から1時間未満は残し、1時間以上で削除する", () => {
    for (const elapsedMs of [CLOSED_GRACE_MS - 1, CLOSED_GRACE_MS, CLOSED_GRACE_MS + 1]) {
      const result = plan({
        closedRooms: { [ROOM_CODE]: closedRoom() },
        records: { [ROOM_CODE]: record(NOW_EPOCH_MS - elapsedMs) },
      });
      assert.deepEqual(result.recordsToSet, {});
      assert.deepEqual(result.recordsToRemove, []);
      assert.deepEqual(result.roomsToDelete, elapsedMs < CLOSED_GRACE_MS ? [] : [
        { code: ROOM_CODE, roomInstanceID: ROOM_INSTANCE_ID, requireClosed: true },
      ]);
    }
  });

  it("同じコードの新しいclosedは観測記録を作り直す", () => {
    const newInstanceID = "room-recreated";
    assert.deepEqual(plan({
      closedRooms: { [ROOM_CODE]: closedRoom(newInstanceID) },
      records: { [ROOM_CODE]: record(NOW_EPOCH_MS - CLOSED_GRACE_MS) },
    }), {
      recordsToSet: { [ROOM_CODE]: record(NOW_EPOCH_MS, newInstanceID) },
      recordsToRemove: [],
      roomsToDelete: [],
    });
  });

  it("closedでなくなったルームの記録を消し、クエリ上限時は保持する", () => {
    const records = { [ROOM_CODE]: record(NOW_EPOCH_MS - CLOSED_GRACE_MS) };
    assert.deepEqual(plan({ records }).recordsToRemove, [ROOM_CODE]);

    const closedRooms = Object.fromEntries(Array.from(
      { length: MAX_ROOMS_PER_RUN },
      (_, index) => [String(1_000 + index), closedRoom(`room-${index}`)]
    ));
    assert.deepEqual(plan({ closedRooms, records }).recordsToRemove, []);
  });

  it("24時間以上前に作成されたwaitingはstatusにかかわらず削除する", () => {
    const result = plan({
      staleRooms: {
        [ROOM_CODE]: {
          roomInstanceID: ROOM_INSTANCE_ID,
          status: "waiting",
          createdAt: NOW_EPOCH_MS - STALE_ROOM_MS,
        },
      },
    });
    assert.deepEqual(result.roomsToDelete, [
      { code: ROOM_CODE, roomInstanceID: ROOM_INSTANCE_ID, requireClosed: false },
    ]);
  });

  it("createdAtがない、または数値でないルームには24時間の規則を適用しない", () => {
    for (const createdAt of [undefined, null, String(NOW_EPOCH_MS - STALE_ROOM_MS)]) {
      assert.deepEqual(plan({
        staleRooms: {
          [ROOM_CODE]: { roomInstanceID: ROOM_INSTANCE_ID, status: "waiting", createdAt },
        },
      }).roomsToDelete, []);
    }
  });
});
