const { createHash } = require("node:crypto");
const { PROTOCOL_VERSION } = require("./constants");

const QUEUE_BUCKET = "phase-b-open";
const QUEUE_LEASE_MS = 5 * 60 * 1000;
const MAX_INTENT_RESULTS = 16;
const SESSION_STATE = Object.freeze({
  QUEUED: "QUEUED",
  MATCH_FOUND: "MATCH_FOUND",
  WAITING_PLAYERS: "WAITING_PLAYERS",
  FINISHED: "FINISHED",
});

function clone(value) {
  return JSON.parse(JSON.stringify(value ?? {}));
}

function normalized(input) {
  const state = clone(input);
  state.private ||= {};
  state.private.profiles ||= {};
  state.private.queue ||= {};
  state.private.pendingMatches ||= {};
  state.public ||= {};
  return state;
}

function fingerprint(intent, uid) {
  return createHash("sha256").update(JSON.stringify({
    uid,
    type: intent.type,
    protocolVersion: intent.protocolVersion,
    sessionId: intent.sessionId ?? null,
    sessionEpoch: intent.sessionEpoch ?? null,
    payload: intent.payload,
  })).digest("hex");
}

function ack(intent, status, details = {}) {
  return {
    intentId: intent.intentId,
    status,
    rejectionCode: null,
    retryable: false,
    ...details,
  };
}

function rejected(intent, rejectionCode, details = {}) {
  return ack(intent, "REJECTED", { rejectionCode, ...details });
}

function existingResult(profile, intent, uid) {
  const saved = profile?.intentResults?.[intent.intentId];
  if (!saved) return null;
  if (saved.fingerprint !== fingerprint(intent, uid)) {
    return rejected(intent, "INTENT_REPLAY_MISMATCH");
  }
  return { ...saved.ack, status: "DUPLICATE", originalStatus: saved.ack.status };
}

function saveResult(profile, intent, uid, result, nowEpochMs) {
  profile.intentResults ||= {};
  profile.intentResults[intent.intentId] = {
    fingerprint: fingerprint(intent, uid),
    resolvedAtEpochMs: nowEpochMs,
    ack: result,
  };
  const ordered = Object.entries(profile.intentResults)
    .sort(([, left], [, right]) => right.resolvedAtEpochMs - left.resolvedAtEpochMs);
  profile.intentResults = Object.fromEntries(ordered.slice(0, MAX_INTENT_RESULTS));
}

function publicProjection(uid, session, nowEpochMs, extra = {}) {
  return {
    uid,
    state: session.state,
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    protocolVersion: session.protocolVersion,
    updatedAtEpochMs: nowEpochMs,
    ...extra,
  };
}

function processJoinQueue(input, intent, uid, {
  nowEpochMs,
  generatedSessionId,
  accountType,
}) {
  const state = normalized(input);
  let profile = state.private.profiles[uid];
  const duplicate = existingResult(profile, intent, uid);
  if (duplicate) return { state, ack: duplicate, changed: false };

  if (profile?.currentSession
      && [SESSION_STATE.MATCH_FOUND, SESSION_STATE.WAITING_PLAYERS]
        .includes(profile.currentSession.state)) {
    const result = rejected(intent, "ACTIVE_MATCH_EXISTS", {
      sessionId: profile.currentSession.sessionId,
      sessionEpoch: profile.currentSession.sessionEpoch,
      matchmakingState: profile.currentSession.state,
      matchId: profile.currentSession.matchId ?? null,
    });
    saveResult(profile, intent, uid, result, nowEpochMs);
    return { state, ack: result, changed: true };
  }

  const nextEpoch = (profile?.lastSessionEpoch || 0) + 1;
  const session = {
    sessionId: generatedSessionId,
    sessionEpoch: nextEpoch,
    state: SESSION_STATE.QUEUED,
    matchId: null,
    protocolVersion: PROTOCOL_VERSION,
    matchmakingBucket: QUEUE_BUCKET,
    leaseExpiresAtEpochMs: nowEpochMs + QUEUE_LEASE_MS,
    updatedAtEpochMs: nowEpochMs,
  };
  profile ||= {
    uid,
    createdAtEpochMs: nowEpochMs,
    accountStatus: "ACTIVE",
    intentResults: {},
  };
  profile.accountType = accountType;
  profile.protocolVersion = PROTOCOL_VERSION;
  profile.lastSessionEpoch = nextEpoch;
  profile.currentSession = session;
  profile.matchmaking = { bucket: QUEUE_BUCKET, source: "UNRATED_PHASE_B" };
  profile.updatedAtEpochMs = nowEpochMs;
  state.private.profiles[uid] = profile;
  state.private.queue[uid] = {
    uid,
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    queuedAtEpochMs: nowEpochMs,
    leaseExpiresAtEpochMs: session.leaseExpiresAtEpochMs,
    protocolVersion: PROTOCOL_VERSION,
    matchmakingBucket: QUEUE_BUCKET,
  };
  state.public[uid] = publicProjection(uid, session, nowEpochMs, {
    queuedAtEpochMs: nowEpochMs,
  });
  const result = ack(intent, "ACCEPTED", {
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    matchmakingState: SESSION_STATE.QUEUED,
  });
  saveResult(profile, intent, uid, result, nowEpochMs);
  return { state, ack: result, changed: true };
}

function processCancelQueue(input, intent, uid, nowEpochMs) {
  const state = normalized(input);
  const profile = state.private.profiles[uid];
  const duplicate = existingResult(profile, intent, uid);
  if (duplicate) return { state, ack: duplicate, changed: false };
  if (!profile?.currentSession) {
    return { state, ack: rejected(intent, "SESSION_NOT_ACTIVE"), changed: false };
  }
  const session = profile.currentSession;
  if (session.sessionId !== intent.sessionId || session.sessionEpoch !== intent.sessionEpoch) {
    const result = rejected(intent, "STALE_SESSION_EPOCH");
    saveResult(profile, intent, uid, result, nowEpochMs);
    return { state, ack: result, changed: true };
  }
  if (session.state !== SESSION_STATE.QUEUED) {
    const result = rejected(
      intent,
      [SESSION_STATE.MATCH_FOUND, SESSION_STATE.WAITING_PLAYERS].includes(session.state)
        ? "MATCH_ALREADY_ASSIGNED"
        : "SESSION_NOT_ACTIVE"
    );
    saveResult(profile, intent, uid, result, nowEpochMs);
    return { state, ack: result, changed: true };
  }

  delete state.private.queue[uid];
  session.state = SESSION_STATE.FINISHED;
  session.leaseExpiresAtEpochMs = nowEpochMs;
  session.updatedAtEpochMs = nowEpochMs;
  profile.updatedAtEpochMs = nowEpochMs;
  state.public[uid] = publicProjection(uid, session, nowEpochMs, {
    state: "NOT_QUEUED",
  });
  const result = ack(intent, "ACCEPTED", {
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    matchmakingState: "NOT_QUEUED",
  });
  saveResult(profile, intent, uid, result, nowEpochMs);
  return { state, ack: result, changed: true };
}

function expireStaleQueue(state, nowEpochMs) {
  let changed = false;
  for (const [uid, entry] of Object.entries(state.private.queue)) {
    if (entry.leaseExpiresAtEpochMs > nowEpochMs) continue;
    delete state.private.queue[uid];
    const profile = state.private.profiles[uid];
    const session = profile?.currentSession;
    if (session?.state === SESSION_STATE.QUEUED
        && session.sessionId === entry.sessionId
        && session.sessionEpoch === entry.sessionEpoch) {
      session.state = SESSION_STATE.FINISHED;
      session.updatedAtEpochMs = nowEpochMs;
      profile.updatedAtEpochMs = nowEpochMs;
      state.public[uid] = publicProjection(uid, session, nowEpochMs, {
        state: "NOT_QUEUED",
      });
    }
    changed = true;
  }
  return changed;
}

function claimNextMatch(input, {
  nowEpochMs,
  matchId,
  assignmentTickets,
}) {
  const state = normalized(input);
  let changed = expireStaleQueue(state, nowEpochMs);
  const candidates = Object.values(state.private.queue)
    .filter((entry) => {
      const session = state.private.profiles[entry.uid]?.currentSession;
      return entry.protocolVersion === PROTOCOL_VERSION
        && entry.matchmakingBucket === QUEUE_BUCKET
        && entry.leaseExpiresAtEpochMs > nowEpochMs
        && session?.state === SESSION_STATE.QUEUED
        && session.sessionId === entry.sessionId
        && session.sessionEpoch === entry.sessionEpoch;
    })
    .sort((left, right) => left.queuedAtEpochMs - right.queuedAtEpochMs
      || left.uid.localeCompare(right.uid));
  if (candidates.length < 4) return { state, claimed: null, changed };

  const selected = candidates.slice(0, 4);
  const participants = selected.map((entry, slot) => {
    const profile = state.private.profiles[entry.uid];
    const session = profile.currentSession;
    session.state = SESSION_STATE.MATCH_FOUND;
    session.matchId = matchId;
    session.leaseExpiresAtEpochMs = null;
    session.updatedAtEpochMs = nowEpochMs;
    profile.updatedAtEpochMs = nowEpochMs;
    delete state.private.queue[entry.uid];
    state.public[entry.uid] = publicProjection(entry.uid, session, nowEpochMs, {
      matchId,
      assignmentTicket: assignmentTickets[slot],
    });
    return {
      uid: entry.uid,
      slot,
      sessionId: session.sessionId,
      sessionEpoch: session.sessionEpoch,
      assignmentTicket: assignmentTickets[slot],
    };
  });
  const claimed = {
    matchId,
    status: "CLAIMED",
    protocolVersion: PROTOCOL_VERSION,
    matchmakingBucket: QUEUE_BUCKET,
    claimedAtEpochMs: nowEpochMs,
    participants,
  };
  state.private.pendingMatches[matchId] = claimed;
  changed = true;
  return { state, claimed, changed };
}

function finalizeClaim(input, matchId, nowEpochMs) {
  const state = normalized(input);
  const pending = state.private.pendingMatches[matchId];
  if (!pending) return { state, finalized: false, changed: false };
  for (const participant of pending.participants) {
    const profile = state.private.profiles[participant.uid];
    const session = profile?.currentSession;
    if (!session
        || session.sessionId !== participant.sessionId
        || session.sessionEpoch !== participant.sessionEpoch
        || session.matchId !== matchId) {
      throw new Error("MATCH_CLAIM_FENCE_MISMATCH");
    }
    session.state = SESSION_STATE.WAITING_PLAYERS;
    session.updatedAtEpochMs = nowEpochMs;
    profile.updatedAtEpochMs = nowEpochMs;
    state.public[participant.uid] = publicProjection(participant.uid, session, nowEpochMs, {
      matchId,
      assignmentTicket: participant.assignmentTicket,
    });
  }
  delete state.private.pendingMatches[matchId];
  return { state, finalized: true, changed: true };
}

function releaseFinishedMatch(input, matchId, nowEpochMs) {
  const state = normalized(input);
  let changed = false;
  for (const [uid, profile] of Object.entries(state.private.profiles)) {
    const session = profile.currentSession;
    if (session?.matchId !== matchId) continue;
    session.state = SESSION_STATE.FINISHED;
    session.matchId = null;
    session.updatedAtEpochMs = nowEpochMs;
    profile.updatedAtEpochMs = nowEpochMs;
    state.public[uid] = publicProjection(uid, session, nowEpochMs, {
      state: "NOT_QUEUED",
    });
    changed = true;
  }
  return { state, changed };
}

module.exports = {
  QUEUE_BUCKET,
  QUEUE_LEASE_MS,
  SESSION_STATE,
  claimNextMatch,
  finalizeClaim,
  processCancelQueue,
  processJoinQueue,
  releaseFinishedMatch,
};
