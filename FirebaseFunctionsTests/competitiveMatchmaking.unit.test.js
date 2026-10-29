const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  PROTOCOL_VERSION,
} = require("../functions/competitive/constants");
const { validateMatchmakingIntent } = require("../functions/competitive/matchmakingContract");
const { RATING_CONFIG, TIER } = require("../functions/competitive/rating");
const {
  SESSION_STATE,
  claimNextMatch,
  finalizeClaim,
  processCancelQueue,
  processCheckQueue,
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

  it("enforces Explicit Forfeit cooldown on the server and creates a new session after five seconds", () => {
    const initial = addPlayer({}, "p1", 0).state;
    const profile = initial.private.profiles.p1;
    profile.currentSession.state = SESSION_STATE.WAITING_PLAYERS;
    profile.currentSession.matchId = "match-old";
    profile.currentSession.assignmentTicket = "ticket-old";
    delete initial.private.queue.p1;
    profile.explicitForfeitCooldown = {
      matchId: "match-old",
      sessionId: profile.currentSession.sessionId,
      sessionEpoch: profile.currentSession.sessionEpoch,
      forfeitCompletedAtEpochMs: 1_000,
      cooldownEndsAtEpochMs: 6_000,
    };

    const early = processJoinQueue(initial, joinIntent("p1", "cooldown-early"), "p1", {
      nowEpochMs: 5_999,
      generatedSessionId: "session-too-early",
      accountType: "ANONYMOUS",
    });
    assert.equal(early.ack.rejectionCode, "FORFEIT_COOLDOWN_ACTIVE");
    assert.equal(early.ack.cooldownEndsAtEpochMs, 6_000);
    assert.equal(early.state.private.queue.p1, undefined);
    assert.equal(early.state.private.profiles.p1.currentSession.state, SESSION_STATE.FINISHED);
    assert.equal(early.state.private.profiles.p1.currentSession.matchId, null);
    assert.equal(early.state.private.profiles.p1.currentSession.assignmentTicket, undefined);

    const accepted = processJoinQueue(
      early.state,
      joinIntent("p1", "cooldown-complete"),
      "p1",
      {
        nowEpochMs: 6_000,
        generatedSessionId: "session-new",
        accountType: "ANONYMOUS",
      }
    );
    assert.equal(accepted.ack.status, "ACCEPTED");
    assert.equal(accepted.ack.sessionId, "session-new");
    assert.equal(accepted.ack.sessionEpoch, 2);
    assert.equal(accepted.state.private.profiles.p1.explicitForfeitCooldown, undefined);
    assert.equal(accepted.state.public.p1.cooldownEndsAtEpochMs, undefined);
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

  it("waits five seconds before filling Bronze vacancies with server-owned NPCs", () => {
    const joined = addPlayer({}, "p1", 0);
    assert.equal(joined.ack.nextCheckAfterMs, RATING_CONFIG.npcFillWaitMs.BRONZE);
    assert.equal(
      joined.state.public.p1.nextCheckAfterMs,
      RATING_CONFIG.npcFillWaitMs.BRONZE
    );
    let queued = joined.state;
    queued = addPlayer(queued, "p2", 1).state;
    queued = addPlayer(queued, "p3", 2).state;
    assert.equal(claim(queued, "too-early", 5_999).claimed, null);

    const result = claim(queued, "npc-match", 6_002);
    assert.equal(result.claimed.participants.length, 4);
    assert.equal(result.claimed.participants.filter((player) => player.kind === "HUMAN").length, 3);
    assert.equal(result.claimed.participants.filter((player) => player.kind === "NPC").length, 1);
    const finalized = finalizeClaim(result.state, "npc-match", 6_100);
    assert.equal(finalized.finalized, true);
    assert.equal(result.state.public.p1.competitive.currentTier, TIER.BRONZE);
    assert.equal(result.state.public.p1.competitive.displayRating, undefined);
    assert.equal(JSON.stringify(result.state.public.p1).includes("hiddenRating"), false);
  });

  it("derives NPC skill and one difficulty band from the human-only average MMR", () => {
    let state = addPlayers(2);
    state.private.profiles.p1.competitive.hiddenRating = 1_100;
    state.private.profiles.p2.competitive.hiddenRating = 1_300;
    const result = claim(state, "rating-npc", 11_100);
    assert.equal(result.claimed.ratingContext.averageHumanRating, 1_200);
    assert.equal(result.claimed.ratingContext.npcSkillInput.sourceAverageHiddenRating, 1_200);
    assert.equal(result.claimed.ratingContext.npcSkillInput.strengthProfileId, "VERY_STRONG");
    assert.equal(result.claimed.ratingContext.npcSkillInput.accuracyPermille, 750);
    assert.equal(result.claimed.ratingContext.npcSkillInput.reactionBaseMs, undefined);
    assert.ok(result.claimed.participants
      .filter((participant) => participant.kind === "NPC")
      .every((participant) => participant.preMatchRating === 1_200));
    assert.equal(result.claimed.ratingContext.questionSelection.subject, "ENGLISH");
    assert.equal(result.claimed.ratingContext.questionSelection.matchTier, TIER.SILVER);
    assert.deepEqual(result.claimed.ratingContext.questionSelection.difficultyBand, {
      minimum: 2,
      maximum: 3,
    });
    assert.equal(
      result.claimed.ratingContext.questionSelection.mappingStatus,
      "PRODUCT_MAPPING_CONFIRMED"
    );
  });

  it("waits ten seconds for Silver and never fills Gold-or-higher with NPCs", () => {
    const state = addPlayers(1);
    state.private.profiles.p1.competitive.hiddenRating = 1_200;
    assert.equal(claim(state, "silver-early", 10_999).claimed, null);
    const silver = claim(state, "silver-fill", 11_000);
    assert.equal(silver.claimed.participants.filter((player) => player.kind === "HUMAN").length, 1);

    const gold = addPlayers(1);
    gold.private.profiles.p1.competitive.hiddenRating = 1_400;
    assert.equal(claim(gold, "gold-human-only", 60_000).claimed, null);
  });

  it("uses the highest human tier for mixed NPC fill policy", () => {
    let bronzeSilver = addPlayers(2);
    bronzeSilver.private.profiles.p1.competitive.hiddenRating = 1_100;
    bronzeSilver.private.profiles.p2.competitive.hiddenRating = 1_200;
    assert.equal(claim(bronzeSilver, "mixed-early", 6_100).claimed, null);
    assert.ok(claim(bronzeSilver, "mixed-silver", 11_100).claimed);

    let bronzeGold = addPlayers(2);
    bronzeGold.private.profiles.p1.competitive.hiddenRating = 1_100;
    bronzeGold.private.profiles.p2.competitive.hiddenRating = 1_400;
    assert.equal(claim(bronzeGold, "mixed-gold", 60_000).claimed, null);
  });

  it("fills one to three human rosters but never adds NPC to an immediate four-human match", () => {
    for (let humanCount = 1; humanCount <= 3; humanCount += 1) {
      const result = claim(addPlayers(humanCount), `npc-${humanCount}`, 6_100);
      assert.equal(result.claimed.participants.filter((player) => player.kind === "HUMAN").length, humanCount);
      assert.equal(result.claimed.participants.filter((player) => player.kind === "NPC").length, 4 - humanCount);
    }
    const humanOnly = claim(addPlayers(4), "human-only", 1_100);
    assert.ok(humanOnly.claimed.participants.every((player) => player.kind === "HUMAN"));
  });

  it("validates the queue check with the active session fence", () => {
    const state = addPlayers(1);
    const session = state.private.profiles.p1.currentSession;
    const intent = {
      intentId: "check-p1",
      type: "checkQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-unit",
      sessionId: session.sessionId,
      sessionEpoch: session.sessionEpoch,
      payload: {},
    };
    assert.equal(validateMatchmakingIntent(intent), null);
    assert.equal(processCheckQueue(state, intent, "p1", 1_100).ack.status, "ACCEPTED");
    assert.equal(processCheckQueue(state, {
      ...intent,
      intentId: "check-p1-stale",
      sessionEpoch: 99,
    }, "p1", 1_100)
      .ack.rejectionCode, "STALE_SESSION_EPOCH");
  });
});
