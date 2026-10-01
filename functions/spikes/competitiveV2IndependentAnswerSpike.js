const { randomUUID, timingSafeEqual } = require("node:crypto");
const { performance } = require("node:perf_hooks");
const { getApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");

const REGION = "asia-southeast1";
const ROOT_PATH = "__spikes/competitiveV2OrderingA";
const PLAYERS = ["A", "B", "C", "D"];
const CORRECT_ANSWER_ID = "answer-correct";
const VALID_ANSWER_IDS = new Set([
  CORRECT_ANSWER_ID,
  "answer-wrong-1",
  "answer-wrong-2",
  "answer-wrong-3",
]);
const MAX_BODY_BYTES = 4_096;
const MAX_CAS_ATTEMPTS = 20;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/;
const SPIKE_TOKEN = defineSecret("COMPETITIVE_V2_SPIKE_TOKEN");
const INSTANCE_ID = randomUUID();
const INSTANCE_STARTED_AT_EPOCH_MS = Date.now();

let orderingInvocationOrdinal = 0;
let cachedAccessToken = null;
let accessTokenExpiresAtEpochMs = 0;

const COMMON_OPTIONS = {
  region: REGION,
  memory: "256MiB",
  cpu: 1,
  timeoutSeconds: 30,
  minInstances: 0,
  maxInstances: 4,
  invoker: "public",
  secrets: [SPIKE_TOKEN],
};

const CONTROL_OPTIONS = { ...COMMON_OPTIONS, concurrency: 20 };
// Spike-only setting: make four concurrent answers spread across instances.
const ORDER_OPTIONS = { ...COMMON_OPTIONS, concurrency: 1 };

function sendJson(response, statusCode, body) {
  response.set("cache-control", "no-store");
  response.status(statusCode).json(body);
}

function bodySize(request) {
  if (Buffer.isBuffer(request.rawBody)) return request.rawBody.length;
  return Buffer.byteLength(JSON.stringify(request.body ?? null), "utf8");
}

function sameSecret(actual, expected) {
  if (typeof actual !== "string" || typeof expected !== "string") return false;
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

function validateAnswerIntent(intent) {
  const allowed = new Set([
    "runId",
    "matchId",
    "questionId",
    "answerId",
    "eventId",
    "sessionId",
    "sessionEpoch",
  ]);
  if (!isPlainObject(intent)
      || !containsOnlyKeys(intent, allowed)
      || !isSafeId(intent.runId)
      || !isSafeId(intent.matchId)
      || !isSafeId(intent.questionId)
      || !isSafeId(intent.answerId)
      || !isSafeId(intent.eventId)
      || !isSafeId(intent.sessionId)
      || !Number.isSafeInteger(intent.sessionEpoch)
      || intent.sessionEpoch < 1) {
    return "MALFORMED_REQUEST";
  }
  return null;
}

function validateControlRequest(body) {
  if (!isPlainObject(body) || !isSafeId(body.runId)) return "MALFORMED_REQUEST";
  const actions = new Set(["initialize", "initializeTie", "status", "close", "cleanup"]);
  if (!actions.has(body.action)) return "MALFORMED_REQUEST";
  if (body.action === "cleanup") {
    return containsOnlyKeys(body, new Set(["action", "runId"]))
      ? null
      : "MALFORMED_REQUEST";
  }
  if (!isSafeId(body.matchId)) return "MALFORMED_REQUEST";
  if (body.action === "initialize") {
    return containsOnlyKeys(body, new Set(["action", "runId", "matchId", "durationMs"]))
      && Number.isSafeInteger(body.durationMs)
      && body.durationMs >= 1
      && body.durationMs <= 120_000
      ? null
      : "MALFORMED_REQUEST";
  }
  if (body.action === "close") {
    return containsOnlyKeys(
      body,
      new Set(["action", "runId", "matchId", "questionId", "reason", "closeEventId"])
    )
      && isSafeId(body.questionId)
      && ["ALL_ANSWERED", "DEADLINE"].includes(body.reason)
      && isSafeId(body.closeEventId)
      ? null
      : "MALFORMED_REQUEST";
  }
  return containsOnlyKeys(body, new Set(["action", "runId", "matchId"]))
    ? null
    : "MALFORMED_REQUEST";
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

function answerRestUrl(runId, matchId, playerId) {
  return `${databaseUrl()}/${ROOT_PATH}/${runId}/matches/${matchId}/answers/${playerId}.json`;
}

function clockRestUrl(runId, clockId) {
  return `${databaseUrl()}/${ROOT_PATH}/${runId}/clocks/${clockId}.json`;
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
  if (!result?.access_token) throw new Error("ADMIN_ACCESS_TOKEN_UNAVAILABLE");
  cachedAccessToken = result.access_token;
  accessTokenExpiresAtEpochMs = now + (result.expires_in || 3_600) * 1_000;
  return { token: cachedAccessToken, cacheHit: false };
}

function operations() {
  return { reads: 0, writeAttempts: 0, successfulWrites: 0, contentionRetries: 0 };
}

async function restRead(url, accessToken, counts, includeEtag = false) {
  counts.reads += 1;
  const response = await fetch(url, {
    headers: {
      authorization: `Bearer ${accessToken}`,
      ...(includeEtag ? { "x-firebase-etag": "true" } : {}),
    },
  });
  if (!response.ok) throw new Error(`RTDB_READ_HTTP_${response.status}`);
  return {
    value: await response.json(),
    etag: response.headers.get("etag"),
  };
}

async function restConditionalPut(url, value, etag, accessToken, counts) {
  counts.writeAttempts += 1;
  const response = await fetch(url, {
    method: "PUT",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
      "if-match": etag,
    },
    body: JSON.stringify(value),
  });
  if (response.status === 412) {
    counts.contentionRetries += 1;
    return { contention: true, value: null };
  }
  if (!response.ok) throw new Error(`RTDB_WRITE_HTTP_${response.status}`);
  counts.successfulWrites += 1;
  return { contention: false, value: await response.json() };
}

async function rtdbServerTimestamp(runId, clockId, accessToken, counts) {
  counts.writeAttempts += 1;
  const response = await fetch(clockRestUrl(runId, clockId), {
    method: "PUT",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ atEpochMs: { ".sv": "timestamp" } }),
  });
  if (!response.ok) throw new Error(`RTDB_CLOCK_HTTP_${response.status}`);
  counts.successfulWrites += 1;
  const value = await response.json();
  if (!Number.isFinite(value?.atEpochMs)) throw new Error("RTDB_CLOCK_UNRESOLVED");
  return value.atEpochMs;
}

function initialState(openedAtEpochMs, durationMs, answers = {}) {
  return {
    schemaVersion: 2,
    spikeModel: "independent-close-order",
    phase: "QUESTION_OPEN",
    stateVersion: 0,
    questionId: "spike-question-1",
    questionOpenedAtEpochMs: openedAtEpochMs,
    questionDeadlineEpochMs: openedAtEpochMs + durationMs,
    participantOrder: PLAYERS,
    players: Object.fromEntries(
      PLAYERS.map((playerId) => [
        playerId,
        { sessionId: `session-${playerId}`, sessionEpoch: 1 },
      ])
    ),
    validAnswerIds: Object.fromEntries(
      [...VALID_ANSWER_IDS].map((answerId) => [answerId, true])
    ),
    correctAnswerId: CORRECT_ANSWER_ID,
    answers,
  };
}

function inspectState(state, intent, playerId) {
  if (!state) return { code: "UNKNOWN_MATCH" };
  if (state.questionId !== intent.questionId) return { code: "STALE_QUESTION" };
  const player = state.players?.[playerId];
  if (!player) return { code: "UNKNOWN_PLAYER" };
  if (player.sessionId !== intent.sessionId
      || player.sessionEpoch !== intent.sessionEpoch) {
    return { code: "STALE_SESSION" };
  }
  if (!state.validAnswerIds?.[intent.answerId]) return { code: "INVALID_ANSWER" };
  const prior = state.answers?.[playerId];
  if (prior) {
    if (prior.eventId === intent.eventId) {
      const acceptedByResult = state.result?.answerEventIds?.[playerId]
        === intent.eventId;
      const acceptedWhileOpen = state.phase === "QUESTION_OPEN"
        && prior.acceptedAtEpochMs <= state.questionDeadlineEpochMs;
      return {
        duplicate: true,
        accepted: acceptedByResult || acceptedWhileOpen,
        code: "DUPLICATE_EVENT",
        acceptedAtEpochMs: prior.acceptedAtEpochMs,
      };
    }
    return { code: "DUPLICATE_ANSWER" };
  }
  if (state.phase !== "QUESTION_OPEN") return { code: "QUESTION_CLOSED" };
  return null;
}

function answerRecord(intent, playerId) {
  return {
    playerId,
    eventId: intent.eventId,
    questionId: intent.questionId,
    answerId: intent.answerId,
    sessionId: intent.sessionId,
    sessionEpoch: intent.sessionEpoch,
    acceptedAtEpochMs: { ".sv": "timestamp" },
  };
}

function runtimeMetadata(accessTokenCacheHit) {
  return {
    functionTarget: process.env.FUNCTION_TARGET || process.env.K_SERVICE || "unknown",
    region: REGION,
    rtdbHost: new URL(databaseUrl()).host,
    instanceId: INSTANCE_ID,
    instanceStartedAtEpochMs: INSTANCE_STARTED_AT_EPOCH_MS,
    invocationOrdinal: orderingInvocationOrdinal,
    coldInstanceInvocation: orderingInvocationOrdinal === 1,
    instanceAgeAtT1Ms: Date.now() - INSTANCE_STARTED_AT_EPOCH_MS,
    accessTokenCacheHit,
  };
}

function finalAnswerDecision(decision, timing, counts, accessTokenCacheHit, components) {
  const t2MonotonicMs = performance.now();
  return {
    ...decision,
    operations: counts,
    runtime: runtimeMetadata(accessTokenCacheHit),
    timing: {
      t1EpochMs: timing.t1EpochMs,
      t2EpochMs: timing.t1EpochMs + (t2MonotonicMs - timing.t1MonotonicMs),
      t1ToT2Ms: t2MonotonicMs - timing.t1MonotonicMs,
      accessTokenMs: components.rtdbStartedMonotonicMs
        - components.accessTokenStartedMonotonicMs,
      rtdbMs: t2MonotonicMs - components.rtdbStartedMonotonicMs,
    },
  };
}

async function submitIndependentAnswer(intent, playerId, timing) {
  const counts = operations();
  const validationError = validateAnswerIntent(intent);
  if (validationError) {
    return {
      status: "rejected",
      accepted: false,
      code: validationError,
      operations: counts,
      runtime: runtimeMetadata(null),
      timing: { t1EpochMs: timing.t1EpochMs, t1ToT2Ms: 0 },
    };
  }
  if (!PLAYERS.includes(playerId)) {
    return {
      status: "rejected",
      accepted: false,
      code: "UNAUTHENTICATED",
      operations: counts,
      runtime: runtimeMetadata(null),
      timing: { t1EpochMs: timing.t1EpochMs, t1ToT2Ms: 0 },
    };
  }

  const accessTokenStartedMonotonicMs = performance.now();
  const accessToken = await adminAccessToken();
  const rtdbStartedMonotonicMs = performance.now();
  const components = { accessTokenStartedMonotonicMs, rtdbStartedMonotonicMs };
  const rootUrl = matchRestUrl(intent.runId, intent.matchId);
  const childUrl = answerRestUrl(intent.runId, intent.matchId, playerId);

  const initial = await restRead(rootUrl, accessToken.token, counts);
  const inspection = inspectState(initial.value, intent, playerId);
  if (inspection) {
    return finalAnswerDecision(
      inspection.duplicate
        ? {
          status: "duplicate",
          accepted: inspection.accepted,
          code: inspection.code,
          acceptedAtEpochMs: inspection.acceptedAtEpochMs,
        }
        : { status: "rejected", accepted: false, code: inspection.code },
      timing,
      counts,
      accessToken.cacheHit,
      components
    );
  }

  const write = await restConditionalPut(
    childUrl,
    answerRecord(intent, playerId),
    "null_etag",
    accessToken.token,
    counts
  );
  if (write.contention) {
    const currentAnswer = await restRead(childUrl, accessToken.token, counts);
    const currentState = await restRead(rootUrl, accessToken.token, counts);
    const sameEvent = currentAnswer.value?.eventId === intent.eventId;
    const included = currentState.value?.result?.answerEventIds?.[playerId]
      === intent.eventId;
    const acceptedWhileOpen = currentState.value?.phase === "QUESTION_OPEN"
      && currentAnswer.value?.acceptedAtEpochMs
        <= currentState.value?.questionDeadlineEpochMs;
    return finalAnswerDecision(
      sameEvent
        ? {
          status: "duplicate",
          accepted: included || acceptedWhileOpen,
          code: "DUPLICATE_EVENT",
          acceptedAtEpochMs: currentAnswer.value.acceptedAtEpochMs,
        }
        : { status: "rejected", accepted: false, code: "DUPLICATE_ANSWER" },
      timing,
      counts,
      accessToken.cacheHit,
      components
    );
  }

  const acceptedAtEpochMs = write.value?.acceptedAtEpochMs;
  if (!Number.isFinite(acceptedAtEpochMs)) throw new Error("RTDB_TIMESTAMP_UNRESOLVED");
  const finalState = (await restRead(rootUrl, accessToken.token, counts)).value;
  const included = finalState?.result?.answerEventIds?.[playerId] === intent.eventId;
  let decision;
  if (finalState?.phase === "QUESTION_RESULT") {
    decision = included
      ? { status: "accepted", accepted: true, code: null, acceptedAtEpochMs }
      : { status: "rejected", accepted: false, code: "QUESTION_CLOSED", acceptedAtEpochMs };
  } else if (acceptedAtEpochMs > finalState.questionDeadlineEpochMs) {
    decision = {
      status: "rejected",
      accepted: false,
      code: "DEADLINE_EXCEEDED",
      acceptedAtEpochMs,
    };
  } else {
    decision = { status: "accepted", accepted: true, code: null, acceptedAtEpochMs };
  }
  return finalAnswerDecision(
    decision,
    timing,
    counts,
    accessToken.cacheHit,
    components
  );
}

function canonicalResult(state, closeReason, closedAtEpochMs) {
  const tieBreak = new Map(
    state.participantOrder.map((playerId, index) => [playerId, index])
  );
  const orderedAnswers = Object.values(state.answers || {})
    .filter((answer) => state.players?.[answer.playerId]
      && answer.questionId === state.questionId
      && Number.isFinite(answer.acceptedAtEpochMs)
      && answer.acceptedAtEpochMs <= state.questionDeadlineEpochMs)
    .sort((left, right) => {
      if (left.acceptedAtEpochMs === right.acceptedAtEpochMs) {
        return tieBreak.get(left.playerId) - tieBreak.get(right.playerId);
      }
      return left.acceptedAtEpochMs - right.acceptedAtEpochMs;
    });
  const scoreDeltas = Object.fromEntries(PLAYERS.map((playerId) => [playerId, 0]));
  const correctPlayerIds = [];
  const wrongPlayerIds = [];
  const correctPoints = [20, 10, 5];
  for (const answer of orderedAnswers) {
    if (answer.answerId === state.correctAnswerId) {
      const rank = correctPlayerIds.length;
      correctPlayerIds.push(answer.playerId);
      scoreDeltas[answer.playerId] = correctPoints[rank] ?? 1;
    } else {
      wrongPlayerIds.push(answer.playerId);
      scoreDeltas[answer.playerId] = -10;
    }
  }
  const answered = new Set(orderedAnswers.map((answer) => answer.playerId));
  return {
    closeReason,
    closedAtEpochMs,
    answerOrder: orderedAnswers.map((answer) => answer.playerId),
    answerEventIds: Object.fromEntries(
      orderedAnswers.map((answer) => [answer.playerId, answer.eventId])
    ),
    correctPlayerIds,
    wrongPlayerIds,
    unansweredPlayerIds: PLAYERS.filter((playerId) => !answered.has(playerId)),
    scoreDeltas,
  };
}

async function closeQuestion(body) {
  const counts = operations();
  const accessToken = await adminAccessToken();
  const serverNow = await rtdbServerTimestamp(
    body.runId,
    body.closeEventId,
    accessToken.token,
    counts
  );
  const url = matchRestUrl(body.runId, body.matchId);

  for (let attempt = 0; attempt < MAX_CAS_ATTEMPTS; attempt += 1) {
    const { value: state, etag } = await restRead(url, accessToken.token, counts, true);
    if (!state) return { status: "rejected", code: "UNKNOWN_MATCH", operations: counts };
    if (state.questionId !== body.questionId) {
      return { status: "rejected", code: "STALE_QUESTION", operations: counts };
    }
    if (state.phase === "QUESTION_RESULT") {
      return {
        status: "duplicate",
        code: "ALREADY_CLOSED",
        result: state.result,
        operations: counts,
        deadlineAuthorityEpochMs: serverNow,
      };
    }
    const acceptedAnswers = Object.values(state.answers || {}).filter(
      (answer) => Number.isFinite(answer.acceptedAtEpochMs)
        && answer.acceptedAtEpochMs <= state.questionDeadlineEpochMs
    );
    if (body.reason === "ALL_ANSWERED" && acceptedAnswers.length < PLAYERS.length) {
      return { status: "rejected", code: "NOT_ALL_ANSWERED", operations: counts };
    }
    if (body.reason === "DEADLINE" && serverNow <= state.questionDeadlineEpochMs) {
      return {
        status: "rejected",
        code: "DEADLINE_NOT_REACHED",
        operations: counts,
        deadlineAuthorityEpochMs: serverNow,
      };
    }
    const result = canonicalResult(state, body.reason, serverNow);
    const candidate = {
      ...state,
      phase: "QUESTION_RESULT",
      stateVersion: (state.stateVersion || 0) + 1,
      result,
    };
    const write = await restConditionalPut(
      url,
      candidate,
      etag,
      accessToken.token,
      counts
    );
    if (write.contention) continue;
    return {
      status: "accepted",
      code: null,
      result,
      operations: counts,
      deadlineAuthorityEpochMs: serverNow,
    };
  }
  throw new Error("RTDB_CLOSE_CAS_ATTEMPTS_EXCEEDED");
}

async function initializeMatch(runId, matchId, durationMs, tieAnswers = false) {
  const counts = operations();
  const accessToken = await adminAccessToken();
  const openedAt = await rtdbServerTimestamp(
    runId,
    `initialize-${matchId}`,
    accessToken.token,
    counts
  );
  let answers = {};
  if (tieAnswers) {
    answers = Object.fromEntries(
      PLAYERS.map((playerId) => [
        playerId,
        {
          playerId,
          eventId: `tie-${playerId}`,
          questionId: "spike-question-1",
          answerId: CORRECT_ANSWER_ID,
          sessionId: `session-${playerId}`,
          sessionEpoch: 1,
          acceptedAtEpochMs: openedAt,
        },
      ])
    );
  }
  await getDatabase()
    .ref(`${ROOT_PATH}/${runId}/matches/${matchId}`)
    .set(initialState(openedAt, tieAnswers ? 60_000 : durationMs, answers));
  return { openedAt, operations: counts };
}

const competitiveV2OrderingSpikeAControl = onRequest(
  CONTROL_OPTIONS,
  async (request, response) => {
    if (!authorize(request, response)) return;
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
      if (action === "initialize" || action === "initializeTie") {
        const initialized = await initializeMatch(
          runId,
          matchId,
          request.body.durationMs || 60_000,
          action === "initializeTie"
        );
        sendJson(response, 200, {
          status: "initialized",
          runId,
          matchId,
          questionOpenedAtEpochMs: initialized.openedAt,
          operations: initialized.operations,
        });
        return;
      }
      if (action === "close") {
        const result = await closeQuestion(request.body);
        sendJson(response, 200, result);
        return;
      }
      const snapshot = await runReference.child(`matches/${matchId}`).get();
      sendJson(response, 200, {
        status: snapshot.exists() ? "found" : "missing",
        runId,
        matchId,
        state: snapshot.exists() ? snapshot.val() : null,
      });
    } catch (error) {
      console.error("Competitive v2 independent spike control failed", error);
      sendJson(response, 500, { error: "INTERNAL_ERROR" });
    }
  }
);

const competitiveV2OrderingSpikeAOrder = onRequest(
  ORDER_OPTIONS,
  async (request, response) => {
    const t1MonotonicMs = performance.now();
    const timing = { t1EpochMs: Date.now(), t1MonotonicMs };
    if (!authorize(request, response)) return;
    orderingInvocationOrdinal += 1;
    try {
      const playerId = request.get("x-competitive-spike-player-id");
      const decision = await submitIndependentAnswer(
        request.body,
        playerId,
        timing
      );
      sendJson(response, 200, decision);
    } catch (error) {
      console.error("Competitive v2 independent answer spike failed", error);
      sendJson(response, 500, {
        error: "INTERNAL_ERROR",
        runtime: runtimeMetadata(null),
      });
    }
  }
);

module.exports = {
  competitiveV2OrderingSpikeAControl,
  competitiveV2OrderingSpikeAOrder,
};
