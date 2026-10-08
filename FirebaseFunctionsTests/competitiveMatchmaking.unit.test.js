const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { PROTOCOL_VERSION } = require("../functions/competitive/constants");
const { validateMatchmakingIntent } = require("../functions/competitive/matchmakingContract");
const {
  SESSION_STATE,
  claimNextMatch,
  finalizeClaim,
  processCancelQueue,
  processJoinQueue,
  releaseFinishedMatch,
} = require("../functions/competitive/matchmakingCore");

function joinIntent(uid, intentId = `join-${uid}`) {
  return {
    intentId,
    type: "joinQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-b-unit",
    payload: {},
  };
}

function cancelIntent(uid, session, intentId = `cancel-${uid}`) {
  return {
    intentId,
    type: "cancelQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-b-unit",
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    payload: {},
  };
}

function addPlayer(state, uid, index, intentId = `join-${uid}`) {
  return processJoinQueue(state, joinIntent(uid, intentId), uid, {
    nowEpochMs: 1_000 + index,
    generatedSessionId: `session-${uid}-${index}`,
    accountType: "ANONYMOUS",
  });
}

function addPlayers(count) {
  let state = {};
  for (let index = 0; index < count; index += 1) {
    state = addPlayer(state, `p${index + 1}`, index).state;
  }
  return state;
}

function claim(state, matchId, nowEpochMs = 2_000) {
  return claimNextMatch(state, {
    nowEpochMs,
    matchId,
    assignmentTickets: [0, 1, 2, 3].map((slot) => `ticket-${matchId}-${slot}`),
  });
}

describe("Competitive Phase B matchmaking unit", () => {
  it("keeps the queue contract strict and rejects client-owned matchmaking fields", () => {
    const valid = joinIntent("p1");
    assert.equal(validateMatchmakingIntent(valid), null);
    assert.equal(validateMatchmakingIntent({ ...valid, uid: "other" }), "INVALID_PAYLOAD");
    assert.equal(validateMatchmakingIntent({ ...valid, payload: { mmr: 9_999 } }), "INVALID_PAYLOAD");
    assert.equal(validateMatchmakingIntent({ ...valid, rank: "Gold" }), "INVALID_PAYLOAD");
    assert.equal(validateMatchmakingIntent({ ...valid, matchId: "chosen" }), "INVALID_PAYLOAD");
    assert.equal(validateMatchmakingIntent({ ...valid, protocolVersion: "old" }), "PROTOCOL_UNSUPPORTED");
  });

  it("fences retries and older sessions with a monotonically increasing epoch", () => {
    const firstIntent = joinIntent("p1", "stable-join");
    const first = processJoinQueue({}, firstIntent, "p1", {
      nowEpochMs: 1_000,
      generatedSessionId: "session-1",
      accountType: "ANONYMOUS",
    });
    const duplicate = processJoinQueue(first.state, firstIntent, "p1", {
      nowEpochMs: 1_001,
      generatedSessionId: "unused",
      accountType: "ANONYMOUS",
    });
    assert.equal(duplicate.ack.status, "DUPLICATE");
    assert.equal(duplicate.ack.sessionEpoch, 1);

    const replacement = processJoinQueue(first.state, joinIntent("p1", "new-device"), "p1", {
      nowEpochMs: 1_002,
      generatedSessionId: "session-2",
      accountType: "LINKED",
    });
    assert.equal(replacement.ack.sessionEpoch, 2);
    const staleCancel = processCancelQueue(
      replacement.state,
      cancelIntent("p1", { sessionId: "session-1", sessionEpoch: 1 }),
      "p1",
      1_003
    );
    assert.equal(staleCancel.ack.rejectionCode, "STALE_SESSION_EPOCH");
    assert.equal(staleCancel.state.private.queue.p1.sessionEpoch, 2);
  });

  it("atomically claims four humans and creates one fenced pending match", () => {
    const result = claim(addPlayers(4), "match-1");
    assert.equal(result.claimed.participants.length, 4);
    assert.deepEqual(Object.keys(result.state.private.queue), []);
    assert.equal(new Set(result.claimed.participants.map((player) => player.uid)).size, 4);
    for (const participant of result.claimed.participants) {
      const session = result.state.private.profiles[participant.uid].currentSession;
      assert.equal(session.state, SESSION_STATE.MATCH_FOUND);
      assert.equal(session.matchId, "match-1");
    }
    const finalized = finalizeClaim(result.state, "match-1", 2_100);
    assert.equal(finalized.finalized, true);
    assert.equal(finalized.state.private.pendingMatches["match-1"], undefined);
    assert.ok(result.claimed.participants.every((participant) =>
      finalized.state.public[participant.uid].state === SESSION_STATE.WAITING_PLAYERS
    ));
  });

  it("serializes concurrent matchmakers so 8 humans become two disjoint matches", () => {
    const first = claim(addPlayers(8), "match-1");
    const second = claim(first.state, "match-2", 2_001);
    const firstUIDs = new Set(first.claimed.participants.map((player) => player.uid));
    const secondUIDs = new Set(second.claimed.participants.map((player) => player.uid));
    assert.equal(firstUIDs.size, 4);
    assert.equal(secondUIDs.size, 4);
    assert.equal([...firstUIDs].some((uid) => secondUIDs.has(uid)), false);
    assert.deepEqual(Object.keys(second.state.private.queue), []);
  });

  it("supports three disjoint claims for 12 humans without changing the algorithm", () => {
    let state = addPlayers(12);
    const matched = new Set();
    for (let index = 1; index <= 3; index += 1) {
      const result = claim(state, `match-${index}`, 2_000 + index);
      assert.ok(result.claimed);
      for (const participant of result.claimed.participants) {
        assert.equal(matched.has(participant.uid), false);
        matched.add(participant.uid);
      }
      state = result.state;
    }
    assert.equal(matched.size, 12);
    assert.deepEqual(Object.keys(state.private.queue), []);
  });

  it("makes cancellation retry-safe and rejects cancellation after match claim", () => {
    let state = addPlayers(4);
    const queuedSession = state.private.profiles.p1.currentSession;
    const event = cancelIntent("p1", queuedSession, "stable-cancel");
    const cancelled = processCancelQueue(state, event, "p1", 1_100);
    assert.equal(cancelled.ack.status, "ACCEPTED");
    const duplicate = processCancelQueue(cancelled.state, event, "p1", 1_101);
    assert.equal(duplicate.ack.status, "DUPLICATE");

    state = addPlayers(4);
    const claimed = claim(state, "match-claimed");
    const claimedSession = claimed.state.private.profiles.p1.currentSession;
    const lateCancel = processCancelQueue(
      claimed.state,
      cancelIntent("p1", claimedSession, "late-cancel"),
      "p1",
      2_100
    );
    assert.equal(lateCancel.ack.rejectionCode, "MATCH_ALREADY_ASSIGNED");
    assert.equal(lateCancel.state.private.profiles.p1.currentSession.matchId, "match-claimed");
  });

  it("rejects cancellation using another player's session fence", () => {
    const state = addPlayers(2);
    const playerOneSession = state.private.profiles.p1.currentSession;
    const result = processCancelQueue(
      state,
      cancelIntent("p1", playerOneSession, "cancel-other-player"),
      "p2",
      1_100
    );

    assert.equal(result.ack.rejectionCode, "STALE_SESSION_EPOCH");
    assert.equal(result.state.private.queue.p1.sessionId, playerOneSession.sessionId);
    assert.equal(Object.keys(result.state.private.queue).length, 2);
    assert.equal(result.state.private.profiles.p2.currentSession.state, SESSION_STATE.QUEUED);
  });

  it("releases only the sessions fenced to a finished match", () => {
    const claimed = claim(addPlayers(4), "match-finished");
    const released = releaseFinishedMatch(claimed.state, "match-finished", 3_000);
    assert.equal(released.changed, true);
    for (const participant of claimed.claimed.participants) {
      assert.equal(
        released.state.private.profiles[participant.uid].currentSession.state,
        SESSION_STATE.FINISHED
      );
      assert.equal(released.state.private.profiles[participant.uid].currentSession.matchId, null);
    }
  });
});
