const { randomUUID, timingSafeEqual } = require("node:crypto");
const { performance } = require("node:perf_hooks");
const { getApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");

const REGION = "asia-southeast1";
const ROOT_PATH = "__spikes/competitiveV2OrderingA";
const QUESTION_DURATION_MS = 60_000;
const MAX_BODY_BYTES = 4_096;
const MAX_CAS_ATTEMPTS = 20;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/;
const SPIKE_TOKEN = defineSecret("COMPETITIVE_V2_SPIKE_TOKEN");
const INSTANCE_ID = randomUUID();
const INSTANCE_STARTED_AT_EPOCH_MS = Date.now();

let orderingInvocationOrdinal = 0;
let cachedAccessToken = null;
let accessTokenExpiresAtEpochMs = 0;

const FUNCTION_OPTIONS = {
  region: REGION,
  memory: "256MiB",
  cpu: 1,
  timeoutSeconds: 30,
  minInstances: 0,
  maxInstances: 4,
  concurrency: 20,
  invoker: "public",
  secrets: [SPIKE_TOKEN],
};

function sendJson(response, statusCode, body) {
  response.set("cache-control", "no-store");
  response.status(statusCode).json(body);
}

function bodySize(request) {
  if (Buffer.isBuffer(request.rawBody)) {
    return request.rawBody.length;
  }
  return Buffer.byteLength(JSON.stringify(request.body ?? null), "utf8");
}

function sameSecret(actual, expected) {
  if (typeof actual !== "string" || typeof expected !== "string") {
    return false;
  }
  const actualBytes = Buffer.from(actual, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  return actualBytes.length === expectedBytes.length
    && timingSafeEqual(actualBytes, expectedBytes);
}

function authorize(request, response) {
  if (request.method !== "POST") {
    sendJson(response, 405, { error: "METHOD_NOT_ALLOWED" });
    return false;
  }
  if (bodySize(request) > MAX_BODY_BYTES) {
    sendJson(response, 413, { error: "REQUEST_TOO_LARGE" });
    return false;
  }
  if (!sameSecret(request.get("x-competitive-spike-token"), SPIKE_TOKEN.value())) {
    sendJson(response, 401, { error: "UNAUTHORIZED" });
    return false;
  }
  return true;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function containsOnlyKeys(value, allowedKeys) {
  return Object.keys(value).every((key) => allowedKeys.has(key));
}

function isSafeId(value) {
  return typeof value === "string" && SAFE_ID.test(value);
}

function validateIntent(intent) {
  if (!isPlainObject(intent)
      || !containsOnlyKeys(
        intent,
        new Set(["runId", "matchId", "playerId", "eventId", "sessionId", "sessionEpoch", "buzz"])
      )
      || !isSafeId(intent.runId)
      || !isSafeId(intent.matchId)
      || !isSafeId(intent.playerId)
      || !isSafeId(intent.eventId)
      || !isSafeId(intent.sessionId)
      || !Number.isSafeInteger(intent.sessionEpoch)
      || intent.sessionEpoch < 1
      || intent.buzz !== true) {
    return "MALFORMED_REQUEST";
  }
  return null;
}

function validateControlRequest(body) {
  if (!isPlainObject(body)
      || !containsOnlyKeys(body, new Set(["action", "runId", "matchId"]))
      || !isSafeId(body.runId)
      || ![
        "initialize",
        "status",
        "reopenAfterIncorrect",
        "cleanup",
      ].includes(body.action)) {
    return "MALFORMED_REQUEST";
  }
  if (body.action !== "cleanup" && !isSafeId(body.matchId)) {
    return "MALFORMED_REQUEST";
  }
  if (body.action === "cleanup" && body.matchId !== undefined) {
    return "MALFORMED_REQUEST";
  }
  return null;
}

function initialMatchState() {
  const now = Date.now();
  const players = {};
  const eligiblePlayers = {};
  for (const playerId of ["A", "B", "C", "D"]) {
    players[playerId] = {
      sessionId: `session-${playerId}`,
      sessionEpoch: 1,
    };
    eligiblePlayers[playerId] = true;
  }
  return {
    schemaVersion: 1,
    spikeModel: "first-winner-lock",
    serverSequence: 0,
    stateVersion: 0,
    phase: "QUESTION_OPEN",
    questionId: "spike-question-1",
    questionOpenedAtEpochMs: now,
    questionDeadlineEpochMs: now + QUESTION_DURATION_MS,
    createdAtEpochMs: now,
    players,
    eligiblePlayers,
    lockedOut: {},
    processedEvents: {},
  };
}

function inspectState(state, intent) {
  if (!state) {
    return { status: "rejected", accepted: false, code: "UNKNOWN_MATCH" };
  }
  const player = state.players?.[intent.playerId];
  if (!player) {
    return { status: "rejected", accepted: false, code: "UNKNOWN_PLAYER" };
  }
  if (player.sessionId !== intent.sessionId
      || player.sessionEpoch !== intent.sessionEpoch) {
    return { status: "rejected", accepted: false, code: "STALE_SESSION" };
  }
  const priorEvent = state.processedEvents?.[intent.eventId];
  if (priorEvent) {
    return {
      status: "duplicate",
      code: "DUPLICATE_EVENT",
      accepted: priorEvent.accepted,
      winnerPlayerId: priorEvent.playerId,
      serverSequence: priorEvent.serverSequence,
      stateVersion: priorEvent.stateVersion,
    };
  }
  if (state.lockedOut?.[intent.playerId] === true
      || state.eligiblePlayers?.[intent.playerId] === false) {
    return {
      status: "rejected",
      accepted: false,
      code: "PLAYER_LOCKED_OUT",
      observedSequence: state.serverSequence,
      observedStateVersion: state.stateVersion,
    };
  }
  if (state.winner?.playerId === intent.playerId) {
    return {
      status: "rejected",
      accepted: false,
      code: "DUPLICATE_PLAYER_BUZZ",
      winnerPlayerId: state.winner.playerId,
      observedSequence: state.serverSequence,
      observedStateVersion: state.stateVersion,
    };
  }
  if (state.phase !== "QUESTION_OPEN" || state.winner) {
    return {
      status: "rejected",
      accepted: false,
      code: "BUZZ_ALREADY_LOCKED",
      winnerPlayerId: state.winner?.playerId ?? null,
      observedSequence: state.serverSequence,
      observedStateVersion: state.stateVersion,
    };
  }
  if (Date.now() >= state.questionDeadlineEpochMs) {
    return {
      status: "rejected",
      accepted: false,
      code: "QUESTION_DEADLINE_REACHED",
      observedSequence: state.serverSequence,
      observedStateVersion: state.stateVersion,
    };
  }
  return { status: "ready" };
}

function acceptedState(state, intent, receivedAtEpochMs) {
  const serverSequence = (state.serverSequence || 0) + 1;
  const stateVersion = (state.stateVersion || 0) + 1;
  const winner = {
    accepted: true,
    playerId: intent.playerId,
    eventId: intent.eventId,
    sessionId: intent.sessionId,
    sessionEpoch: intent.sessionEpoch,
    serverSequence,
    stateVersion,
    receivedAtEpochMs,
  };
  return {
    state: {
      ...state,
      serverSequence,
      stateVersion,
      phase: "ANSWERING",
      winner,
      activeResponder: intent.playerId,
      processedEvents: {
        ...(state.processedEvents || {}),
        [intent.eventId]: winner,
      },
    },
    winner,
  };
}

function databaseUrl() {
  const configuredUrl = getDatabase().app.options.databaseURL;
  if (typeof configuredUrl === "string" && configuredUrl.length > 0) {
    return configuredUrl.replace(/\/$/, "");
  }
  let firebaseConfig;
  try {
    firebaseConfig = JSON.parse(process.env.FIREBASE_CONFIG || "{}");
  } catch {
    firebaseConfig = {};
  }
  if (typeof firebaseConfig.databaseURL !== "string") {
    throw new Error("RTDB_DATABASE_URL_UNAVAILABLE");
  }
  return firebaseConfig.databaseURL.replace(/\/$/, "");
}

function matchRestUrl(runId, matchId) {
  return `${databaseUrl()}/${ROOT_PATH}/${runId}/matches/${matchId}.json`;
}

async function adminAccessToken() {
  const now = Date.now();
  if (cachedAccessToken && accessTokenExpiresAtEpochMs - now > 60_000) {
    return { token: cachedAccessToken, cacheHit: true };
  }
  const credential = getApp().options.credential;
  if (!credential || typeof credential.getAccessToken !== "function") {
    throw new Error("ADMIN_CREDENTIAL_UNAVAILABLE");
  }
  const result = await credential.getAccessToken();
  if (!result?.access_token) {
    throw new Error("ADMIN_ACCESS_TOKEN_UNAVAILABLE");
  }
  cachedAccessToken = result.access_token;
  accessTokenExpiresAtEpochMs = now + (result.expires_in || 3_600) * 1_000;
  return { token: cachedAccessToken, cacheHit: false };
}

function finalizeDecision(
  decision,
  timing,
  attemptCounts,
  tokenCacheHit,
  componentTiming = null
) {
  const t2MonotonicMs = performance.now();
  const t1ToT2Ms = t2MonotonicMs - timing.t1MonotonicMs;
  return {
    ...decision,
    attempts: attemptCounts.decisionLoops,
    casWriteAttempts: attemptCounts.casWrites,
    contentionRetries: attemptCounts.contentionRetries,
    runtime: {
      functionTarget: process.env.FUNCTION_TARGET || process.env.K_SERVICE || "unknown",
      region: REGION,
      rtdbHost: new URL(databaseUrl()).host,
      instanceId: INSTANCE_ID,
      instanceStartedAtEpochMs: INSTANCE_STARTED_AT_EPOCH_MS,
      invocationOrdinal: orderingInvocationOrdinal,
      coldInstanceInvocation: orderingInvocationOrdinal === 1,
      instanceAgeAtT1Ms: timing.t1EpochMs - INSTANCE_STARTED_AT_EPOCH_MS,
      accessTokenCacheHit: tokenCacheHit,
    },
    timing: {
      t1EpochMs: timing.t1EpochMs,
      t1HighResolutionEpochMs: timing.t1HighResolutionEpochMs,
      t2EpochMs: timing.t1EpochMs + t1ToT2Ms,
      t1ToT2Ms,
      accessTokenMs: componentTiming
        ? componentTiming.rtdbStartedMonotonicMs
          - componentTiming.accessTokenStartedMonotonicMs
        : null,
      rtdbCasMs: componentTiming
        ? t2MonotonicMs - componentTiming.rtdbStartedMonotonicMs
        : null,
    },
  };
}

async function orderWithRtdbCas(intent, timing) {
  const zeroAttempts = {
    decisionLoops: 0,
    casWrites: 0,
    contentionRetries: 0,
  };
  const validationError = validateIntent(intent);
  if (validationError) {
    return finalizeDecision(
      { status: "rejected", accepted: false, code: validationError },
      timing,
      zeroAttempts,
      null
    );
  }

  const receivedAtEpochMs = Date.now();
  const accessTokenStartedMonotonicMs = performance.now();
  const accessToken = await adminAccessToken();
  const rtdbStartedMonotonicMs = performance.now();
  const componentTiming = {
    accessTokenStartedMonotonicMs,
    rtdbStartedMonotonicMs,
  };
  const url = matchRestUrl(intent.runId, intent.matchId);
  const attemptCounts = {
    decisionLoops: 0,
    casWrites: 0,
    contentionRetries: 0,
  };

  while (attemptCounts.decisionLoops < MAX_CAS_ATTEMPTS) {
    attemptCounts.decisionLoops += 1;
    const readResponse = await fetch(url, {
      headers: {
        authorization: `Bearer ${accessToken.token}`,
        "x-firebase-etag": "true",
      },
    });
    if (!readResponse.ok) {
      throw new Error(`RTDB_READ_HTTP_${readResponse.status}`);
    }

    const state = await readResponse.json();
    const inspection = inspectState(state, intent);
    if (inspection.status !== "ready") {
      return finalizeDecision(
        inspection,
        timing,
        attemptCounts,
        accessToken.cacheHit,
        componentTiming
      );
    }

    const accepted = acceptedState(state, intent, receivedAtEpochMs);
    const etag = readResponse.headers.get("etag");
    if (!etag) {
      throw new Error("RTDB_ETAG_MISSING");
    }

    attemptCounts.casWrites += 1;
    const writeResponse = await fetch(url, {
      method: "PUT",
      headers: {
        authorization: `Bearer ${accessToken.token}`,
        "content-type": "application/json",
        "if-match": etag,
      },
      body: JSON.stringify(accepted.state),
    });
    if (writeResponse.status === 412) {
      attemptCounts.contentionRetries += 1;
      continue;
    }
    if (!writeResponse.ok) {
      throw new Error(`RTDB_CAS_HTTP_${writeResponse.status}`);
    }

    return finalizeDecision(
      {
        status: "accepted",
        accepted: true,
        winnerPlayerId: accepted.winner.playerId,
        serverSequence: accepted.winner.serverSequence,
        stateVersion: accepted.winner.stateVersion,
      },
      timing,
      attemptCounts,
      accessToken.cacheHit,
      componentTiming
    );
  }
  throw new Error("RTDB_CAS_ATTEMPTS_EXCEEDED");
}

async function reopenAfterIncorrect(matchReference) {
  const snapshot = await matchReference.get();
  if (!snapshot.exists()) {
    return { status: "rejected", code: "UNKNOWN_MATCH" };
  }
  const state = snapshot.val();
  if (state.phase !== "ANSWERING" || !state.winner?.playerId) {
    return { status: "rejected", code: "INVALID_REOPEN_STATE" };
  }
  if (Date.now() >= state.questionDeadlineEpochMs) {
    return { status: "rejected", code: "QUESTION_DEADLINE_REACHED" };
  }
  const playerId = state.winner.playerId;
  const reopenedState = {
    ...state,
    serverSequence: (state.serverSequence || 0) + 1,
    stateVersion: (state.stateVersion || 0) + 1,
    phase: "QUESTION_OPEN",
    winner: null,
    activeResponder: null,
    eligiblePlayers: {
      ...(state.eligiblePlayers || {}),
      [playerId]: false,
    },
    lockedOut: {
      ...(state.lockedOut || {}),
      [playerId]: true,
    },
    lastIncorrectPlayerId: playerId,
  };
  await matchReference.set(reopenedState);
  return {
    status: "reopened",
    stateVersion: reopenedState.stateVersion,
    serverSequence: reopenedState.serverSequence,
  };
}

const competitiveV2OrderingSpikeAControl = onRequest(
  FUNCTION_OPTIONS,
  async (request, response) => {
    if (!authorize(request, response)) {
      return;
    }
    const validationError = validateControlRequest(request.body);
    if (validationError) {
      sendJson(response, 400, { error: validationError });
      return;
    }

    const { action, runId, matchId } = request.body;
    const runReference = getDatabase().ref(`${ROOT_PATH}/${runId}`);
    try {
      if (action === "cleanup") {
        await runReference.remove();
        sendJson(response, 200, { status: "cleaned", runId });
        return;
      }
      const matchReference = runReference.child(`matches/${matchId}`);
      if (action === "initialize") {
        await matchReference.set(initialMatchState());
        sendJson(response, 200, { status: "initialized", runId, matchId });
        return;
      }
      if (action === "reopenAfterIncorrect") {
        const result = await reopenAfterIncorrect(matchReference);
        sendJson(response, result.status === "reopened" ? 200 : 409, result);
        return;
      }
      const snapshot = await matchReference.get();
      sendJson(response, 200, {
        status: snapshot.exists() ? "found" : "missing",
        runId,
        matchId,
        state: snapshot.exists() ? snapshot.val() : null,
      });
    } catch (error) {
      console.error("Competitive v2 first-winner spike control failed", error);
      sendJson(response, 500, { error: "INTERNAL_ERROR" });
    }
  }
);

const competitiveV2OrderingSpikeAOrder = onRequest(
  FUNCTION_OPTIONS,
  async (request, response) => {
    const t1MonotonicMs = performance.now();
    const timing = {
      t1EpochMs: Date.now(),
      t1HighResolutionEpochMs: performance.timeOrigin + t1MonotonicMs,
      t1MonotonicMs,
    };
    if (!authorize(request, response)) {
      return;
    }
    orderingInvocationOrdinal += 1;
    try {
      const decision = await orderWithRtdbCas(request.body, timing);
      sendJson(response, 200, decision);
    } catch (error) {
      console.error("Competitive v2 first-winner spike failed", error);
      sendJson(response, 500, {
        error: "INTERNAL_ERROR",
        runtime: {
          functionTarget: process.env.FUNCTION_TARGET || process.env.K_SERVICE || "unknown",
          region: REGION,
          instanceId: INSTANCE_ID,
          invocationOrdinal: orderingInvocationOrdinal,
        },
      });
    }
  }
);

module.exports = {
  competitiveV2OrderingSpikeAControl,
  competitiveV2OrderingSpikeAOrder,
};
