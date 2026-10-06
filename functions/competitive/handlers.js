const { getDatabase, ServerValue } = require("firebase-admin/database");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { performance } = require("node:perf_hooks");
const { randomUUID } = require("node:crypto");
const {
  MAX_BODY_BYTES,
  REGION,
  ROOT_PATH,
  SERVER_VERSION,
} = require("./constants");
const { validateClientIntent, validateReconcileIntent } = require("./contract");
const { processClientIntent, processReconcile } = require("./core");

const FUNCTION_OPTIONS = {
  region: REGION,
  memory: "256MiB",
  cpu: 1,
  timeoutSeconds: 30,
  minInstances: 0,
  maxInstances: 20,
  // Phase A-2ではApp Check境界だけを作り、Production enforcementは有効化しない。
  enforceAppCheck: false,
};

const INSTANCE_ID = randomUUID();
const INSTANCE_STARTED_MONOTONIC_MS = performance.now();
let instanceInvocationCount = 0;

function beginInvocation() {
  const t1MonotonicMs = performance.now();
  instanceInvocationCount += 1;
  return {
    t1MonotonicMs,
    t1EpochMs: performance.timeOrigin + t1MonotonicMs,
    instanceInvocation: instanceInvocationCount,
    instanceAgeAtT1Ms: t1MonotonicMs - INSTANCE_STARTED_MONOTONIC_MS,
  };
}

function withDiagnostics(ack, invocation, authorityTimestampEpochMs = null) {
  const t2MonotonicMs = performance.now();
  return {
    ...ack,
    timing: {
      t1EpochMs: invocation.t1EpochMs,
      t2EpochMs: performance.timeOrigin + t2MonotonicMs,
      t1ToT2Ms: t2MonotonicMs - invocation.t1MonotonicMs,
      authorityTimestampEpochMs,
    },
    runtime: {
      instanceId: INSTANCE_ID,
      instanceInvocation: invocation.instanceInvocation,
      coldInstanceInvocation: invocation.instanceInvocation === 1,
      instanceAgeAtT1Ms: invocation.instanceAgeAtT1Ms,
    },
  };
}

function matchRef(matchId) {
  return getDatabase().ref(`${ROOT_PATH}/matches/${matchId}`);
}

function rejection(intentId, code, state = null) {
  return {
    intentId: intentId || "unknown",
    status: "REJECTED",
    serverSequence: state?.private?.serverSequence ?? null,
    publicStateVersion: state?.private?.stateVersion ?? null,
    rejectionCode: code,
    retryable: code === "INTERNAL_RETRYABLE",
  };
}

function requireAuthenticatedUID(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication is required", {
      rejectionCode: "UNAUTHENTICATED",
    });
  }
  return uid;
}

async function serverTimestamp(matchId, eventId) {
  const reference = getDatabase().ref(`${ROOT_PATH}/clocks/${matchId}/${eventId}`);
  await reference.set(ServerValue.TIMESTAMP);
  const snapshot = await reference.get();
  await reference.remove();
  const value = snapshot.val();
  if (!Number.isFinite(value)) throw new Error("RTDB_SERVER_TIMESTAMP_UNRESOLVED");
  return value;
}

async function readMatch(matchId) {
  const snapshot = await matchRef(matchId).get();
  return snapshot.exists() ? snapshot.val() : null;
}

function preflightAnswer(match, envelope, uid) {
  const state = match?.private;
  if (!state) return "UNKNOWN_MATCH";
  if (state.phase !== "QUESTION_OPEN" || !state.currentQuestion) {
    return "INVALID_MATCH_STATE";
  }
  if (state.currentQuestion.questionId !== envelope.questionId) return "QUESTION_MISMATCH";
  if (!state.currentQuestion.choices.some(
    (choice) => choice.answerId === envelope.payload.answerId
  )) return "INVALID_ANSWER_ID";
  return null;
}

function preflightParticipant(match, envelope, uid) {
  const participant = match?.private?.participants?.[uid];
  if (!participant) return "NOT_MATCH_MEMBER";
  if (participant.sessionId !== envelope.sessionId
      || participant.sessionEpoch !== envelope.sessionEpoch) {
    return "STALE_SESSION_EPOCH";
  }
  return null;
}

async function commitClientIntent(envelope, uid, nowEpochMs, staged) {
  const reference = matchRef(envelope.matchId);
  const initial = await reference.get();
  if (!initial.child("private").exists()) {
    return rejection(envelope.intentId, "UNKNOWN_MATCH");
  }
  const initialValue = initial.val();
  let firstAttempt = true;
  let computation = null;
  const transaction = await reference.transaction((current) => {
    if (current === null && firstAttempt) current = initialValue;
    firstAttempt = false;
    if (!current?.private) {
      computation = null;
      return;
    }
    computation = processClientIntent(
      current,
      envelope,
      uid,
      nowEpochMs,
      staged?.answer || null,
      staged?.errorCode || null
    );
    return computation.match;
  }, undefined, false);
  if (!transaction.committed || !computation || !transaction.snapshot.exists()) {
    return rejection(envelope.intentId, "UNKNOWN_MATCH");
  }
  return computation.ack;
}

async function commitReconcile(envelope, uid, nowEpochMs) {
  const reference = matchRef(envelope.matchId);
  const initial = await reference.get();
  if (!initial.child("private").exists()) {
    return rejection(envelope.intentId, "UNKNOWN_MATCH");
  }
  const initialValue = initial.val();
  let firstAttempt = true;
  let computation = null;
  const transaction = await reference.transaction((current) => {
    if (current === null && firstAttempt) current = initialValue;
    firstAttempt = false;
    if (!current?.private) {
      computation = null;
      return;
    }
    computation = processReconcile(current, envelope, uid, nowEpochMs);
    return computation.match;
  }, undefined, false);
  if (!transaction.committed || !computation || !transaction.snapshot.exists()) {
    return rejection(envelope.intentId, "UNKNOWN_MATCH");
  }
  return computation.ack;
}

function logOutcome(kind, envelope, uid, ack, appCheckPresent) {
  console.info("competitive_core_event", {
    kind,
    matchId: envelope.matchId,
    questionId: envelope.questionId || null,
    playerUID: uid,
    eventId: envelope.intentId,
    status: ack.status,
    rejectionCode: ack.rejectionCode,
    serverSequence: ack.serverSequence,
    publicStateVersion: ack.publicStateVersion,
    protocolVersion: envelope.protocolVersion,
    serverVersion: SERVER_VERSION,
    appCheckPresent,
  });
}

const competitiveIntent = onCall(FUNCTION_OPTIONS, async (request) => {
  const invocation = beginInvocation();
  const uid = requireAuthenticatedUID(request);
  const envelope = request.data;
  const validationError = validateClientIntent(envelope);
  if (validationError) {
    const ack = withDiagnostics(rejection(envelope?.intentId, validationError), invocation);
    logOutcome("intent", envelope || {}, uid, ack, Boolean(request.app));
    return ack;
  }

  try {
    const match = await readMatch(envelope.matchId);
    if (!match) {
      const ack = withDiagnostics(rejection(envelope.intentId, "UNKNOWN_MATCH"), invocation);
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const participantError = preflightParticipant(match, envelope, uid);
    if (participantError) {
      const ack = withDiagnostics(
        rejection(envelope.intentId, participantError, match),
        invocation
      );
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    let preflightError = null;
    if (envelope.type === "submitAnswer") {
      preflightError = preflightAnswer(match, envelope, uid);
    }
    const now = await serverTimestamp(envelope.matchId, envelope.intentId);
    const staged = envelope.type === "submitAnswer" && !preflightError
      ? {
        answer: {
          uid,
          eventId: envelope.intentId,
          questionId: envelope.questionId,
          answerId: envelope.payload.answerId,
          sessionId: envelope.sessionId,
          sessionEpoch: envelope.sessionEpoch,
          acceptedAtEpochMs: now,
        },
        errorCode: null,
      }
      : { answer: null, errorCode: preflightError };
    const ack = withDiagnostics(
      await commitClientIntent(envelope, uid, now, staged),
      invocation,
      now
    );
    logOutcome("intent", envelope, uid, ack, Boolean(request.app));
    return ack;
  } catch (error) {
    console.error("competitive_core_internal", {
      matchId: envelope.matchId,
      eventId: envelope.intentId,
      serverVersion: SERVER_VERSION,
      errorName: error?.name || "Error",
    });
    throw new HttpsError("internal", "Competitive backend failed", {
      rejectionCode: "INTERNAL_RETRYABLE",
    });
  }
});

const competitiveReconcileMatch = onCall(FUNCTION_OPTIONS, async (request) => {
  const invocation = beginInvocation();
  const uid = requireAuthenticatedUID(request);
  const envelope = request.data;
  const validationError = validateReconcileIntent(envelope);
  if (validationError) {
    return withDiagnostics(rejection(envelope?.intentId, validationError), invocation);
  }
  try {
    const match = await readMatch(envelope.matchId);
    if (!match) {
      const ack = withDiagnostics(rejection(envelope.intentId, "UNKNOWN_MATCH"), invocation);
      logOutcome("reconcile", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const participantError = preflightParticipant(match, envelope, uid);
    if (participantError) {
      const ack = withDiagnostics(
        rejection(envelope.intentId, participantError, match),
        invocation
      );
      logOutcome("reconcile", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const now = await serverTimestamp(envelope.matchId, envelope.intentId);
    const ack = withDiagnostics(
      await commitReconcile(envelope, uid, now),
      invocation,
      now
    );
    logOutcome("reconcile", envelope, uid, ack, Boolean(request.app));
    return ack;
  } catch (error) {
    console.error("competitive_core_reconcile_internal", {
      matchId: envelope.matchId,
      eventId: envelope.intentId,
      serverVersion: SERVER_VERSION,
      errorName: error?.name || "Error",
    });
    throw new HttpsError("internal", "Competitive backend failed", {
      rejectionCode: "INTERNAL_RETRYABLE",
    });
  }
});

module.exports = {
  FUNCTION_OPTIONS,
  MAX_BODY_BYTES,
  competitiveIntent,
  competitiveReconcileMatch,
  preflightParticipant,
  withDiagnostics,
};
