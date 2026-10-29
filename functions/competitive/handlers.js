const { getDatabase, ServerValue } = require("firebase-admin/database");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onValueWritten } = require("firebase-functions/v2/database");
const { performance } = require("node:perf_hooks");
const { randomUUID } = require("node:crypto");
const {
  MAX_BODY_BYTES,
  PHASE,
  ROOT_PATH,
  SERVER_VERSION,
} = require("./constants");
const { validateClientIntent, validateReconcileIntent } = require("./contract");
const {
  allActivePlayersAnswered,
  existingIntentOutcome,
  intentFingerprint,
  processClientIntent,
  processPresenceSignal,
  processReconcile,
} = require("./core");
const { FUNCTION_OPTIONS } = require("./functionOptions");
const {
  completeExplicitForfeit,
  releaseFinishedMatchSessions,
  settleFinishedMatch,
} = require("./matchmakingHandlers");

const INSTANCE_ID = randomUUID();
const INSTANCE_STARTED_MONOTONIC_MS = performance.now();
let instanceInvocationCount = 0;
const DATABASE_TRIGGER_REGION = process.env.FUNCTIONS_EMULATOR === "true"
  ? "us-central1"
  : FUNCTION_OPTIONS.region;

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

function withDiagnostics(
  ack,
  invocation,
  authorityTimestampEpochMs = null,
  operation = null
) {
  const t2MonotonicMs = performance.now();
  return {
    ...ack,
    timing: {
      t1EpochMs: invocation.t1EpochMs,
      t2EpochMs: performance.timeOrigin + t2MonotonicMs,
      t1ToT2Ms: t2MonotonicMs - invocation.t1MonotonicMs,
      authorityTimestampEpochMs,
      ...(operation ? { operation } : {}),
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

function answerRef(envelope, uid) {
  return matchRef(envelope.matchId).child(
    `private/answerInbox/${envelope.questionId}/${uid}`
  );
}

function answerIntentRef(envelope) {
  return getDatabase().ref(
    `${ROOT_PATH}/answerIntentClaims/${envelope.matchId}/${envelope.intentId}`
  );
}

function answerCloseClaimRef(envelope) {
  return matchRef(envelope.matchId).child(
    `private/answerCloseClaims/${envelope.questionId}`
  );
}

function activeSessionRef(uid) {
  return getDatabase().ref(
    `${ROOT_PATH}/matchmaking/private/profiles/${uid}/currentSession`
  );
}

async function readExplicitForfeitSettlement(matchId, uid) {
  const snapshot = await getDatabase().ref(
    `${ROOT_PATH}/matchmaking/private/explicitForfeitSettlements/${matchId}/${uid}`
  ).get();
  return snapshot.exists() ? snapshot.val() : null;
}

async function removeForfeitedPresence(matchId, uid) {
  await getDatabase().ref(`${ROOT_PATH}/presence/${matchId}/${uid}`).remove();
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
  if (!state.participants?.[uid]?.active) return "NOT_ACTIVE_PLAYER";
  if (state.participants[uid].status === "RECONNECTING") return "PLAYER_RECONNECTING";
  if (!Number.isSafeInteger(envelope.stateVersion)
      || envelope.stateVersion < state.currentQuestion.openedStateVersion
      || envelope.stateVersion > state.stateVersion) {
    return "STALE_STATE_VERSION";
  }
  if (!state.currentQuestion.choices.some(
    (choice) => choice.answerId === envelope.payload.answerId
  )) return "INVALID_ANSWER_ID";
  return null;
}

async function preflightActiveSession(match, envelope, uid) {
  if (!match?.private?.requiresActiveSessionFence) return null;
  const session = (await activeSessionRef(uid).get()).val();
  if (!session
      || session.sessionId !== envelope.sessionId
      || session.sessionEpoch !== envelope.sessionEpoch
      || session.matchId !== envelope.matchId
      || !["MATCH_FOUND", "WAITING_PLAYERS"].includes(session.state)) {
    return "STALE_ACTIVE_MATCH_SESSION";
  }
  return null;
}

function answerAck(envelope, state, status, rejectionCode = null, originalStatus = null) {
  return {
    intentId: envelope.intentId,
    status,
    serverSequence: state?.private?.serverSequence ?? null,
    publicStateVersion: state?.private?.stateVersion ?? null,
    rejectionCode,
    retryable: false,
    ...(originalStatus ? { originalStatus } : {}),
  };
}

function answerRecordMatches(record, envelope, uid) {
  if (!record || record.uid !== uid || record.eventId !== envelope.intentId) return false;
  const expectedFingerprint = intentFingerprint(envelope, uid);
  if (record.fingerprint) return record.fingerprint === expectedFingerprint;
  return record.questionId === envelope.questionId
    && record.answerId === envelope.payload.answerId
    && record.sessionId === envelope.sessionId
    && record.sessionEpoch === envelope.sessionEpoch;
}

function classifyStoredAnswer(match, envelope, uid, record) {
  if (!match?.private) return { accepted: false, code: "UNKNOWN_MATCH" };
  if (record.status === "ACCEPTED") return { accepted: true, code: null };
  if (record.status === "REJECTED") {
    return { accepted: false, code: record.rejectionCode || "INVALID_MATCH_STATE" };
  }
  const state = match.private;
  const question = state.currentQuestion;
  if (question?.result?.answerEventIds?.[uid] === envelope.intentId) {
    return { accepted: true, code: null };
  }
  if (state.phase !== PHASE.QUESTION_OPEN || !question) {
    return { accepted: false, code: "INVALID_MATCH_STATE" };
  }
  if (question.questionId !== envelope.questionId) {
    return { accepted: false, code: "QUESTION_MISMATCH" };
  }
  const participantError = preflightParticipant(match, envelope, uid);
  if (participantError) return { accepted: false, code: participantError };
  if (!state.participants[uid].active) return { accepted: false, code: "NOT_ACTIVE_PLAYER" };
  if (!Number.isFinite(record.acceptedAtEpochMs)
      || record.acceptedAtEpochMs > question.deadlineEpochMs) {
    return { accepted: false, code: "DEADLINE_EXCEEDED" };
  }
  return { accepted: true, code: null };
}

async function createAnswer(envelope, uid) {
  const reference = answerRef(envelope, uid);
  let transactionAttempts = 0;
  const transaction = await reference.transaction((current) => {
    transactionAttempts += 1;
    if (current !== null) return;
    return {
      uid,
      eventId: envelope.intentId,
      fingerprint: intentFingerprint(envelope, uid),
      questionId: envelope.questionId,
      answerId: envelope.payload.answerId,
      sessionId: envelope.sessionId,
      sessionEpoch: envelope.sessionEpoch,
      acceptedAtEpochMs: ServerValue.TIMESTAMP,
      status: "PENDING",
    };
  }, undefined, false);
  return {
    committed: transaction.committed,
    record: transaction.snapshot.val(),
    reference,
    transactionAttempts,
  };
}

async function claimAnswerIntent(envelope, uid) {
  const reference = answerIntentRef(envelope);
  const fingerprint = intentFingerprint(envelope, uid);
  let transactionAttempts = 0;
  const transaction = await reference.transaction((current) => {
    transactionAttempts += 1;
    if (current !== null) return;
    return {
      fingerprint,
      uid,
      ack: {
        intentId: envelope.intentId,
        status: "PENDING",
        serverSequence: null,
        publicStateVersion: null,
        rejectionCode: null,
        retryable: true,
      },
    };
  }, undefined, false);
  return {
    committed: transaction.committed,
    record: transaction.snapshot.val(),
    reference,
    transactionAttempts,
  };
}

async function finalizeAnswerIntent(claim, ack, authorityTimestampEpochMs) {
  await claim.reference.update({
    ack,
    authorityTimestampEpochMs,
  });
}

async function markAnswerDecision(reference, decision) {
  await reference.update({
    status: decision.accepted ? "ACCEPTED" : "REJECTED",
    rejectionCode: decision.code,
  });
}

async function publishAnswered(envelope, uid) {
  const reference = matchRef(envelope.matchId)
    .child(`public/participants/${uid}`);
  const initial = await reference.get();
  const initialValue = initial.exists() ? initial.val() : null;
  let firstAttempt = true;
  const transaction = await reference.transaction((current) => {
    if (current === null && firstAttempt && initialValue !== null) {
      current = initialValue;
    }
    firstAttempt = false;
    if (!current || current.answerQuestionId !== envelope.questionId) return;
    return { ...current, answered: true };
  }, undefined, false);
  return transaction.committed;
}

async function claimAllAnsweredClose(envelope) {
  const reference = answerCloseClaimRef(envelope);
  const transaction = await reference.transaction((current) => {
    if (current !== null) return;
    return {
      eventId: envelope.intentId,
      claimedAtEpochMs: ServerValue.TIMESTAMP,
    };
  }, undefined, false);
  return transaction.committed;
}

function internalCloseEnvelope(envelope) {
  return {
    ...envelope,
    intentId: `close-${envelope.questionId}`,
    type: "reconcile",
    questionId: undefined,
    stateVersion: undefined,
    payload: {},
  };
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

async function commitReconcile(envelope, uid, nowEpochMs, knownMatch = null) {
  const reference = matchRef(envelope.matchId);
  const initialValue = knownMatch || (await reference.get()).val();
  if (!initialValue?.private) {
    return { ack: rejection(envelope.intentId, "UNKNOWN_MATCH"), phase: null };
  }
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
    return { ack: rejection(envelope.intentId, "UNKNOWN_MATCH"), phase: null };
  }
  return {
    ack: computation.ack,
    phase: transaction.snapshot.child("private/phase").val(),
  };
}

async function commitAnswerIntent(envelope, uid, initialMatch) {
  const intentClaim = await claimAnswerIntent(envelope, uid);
  const expectedFingerprint = intentFingerprint(envelope, uid);
  if (!intentClaim.record || intentClaim.record.fingerprint !== expectedFingerprint) {
    return {
      ack: answerAck(envelope, initialMatch, "REJECTED", "INTENT_REPLAY_MISMATCH"),
      authorityTimestampEpochMs: intentClaim.record?.authorityTimestampEpochMs ?? null,
      answerTransactionAttempts: 0,
      intentTransactionAttempts: intentClaim.transactionAttempts,
    };
  }
  if (intentClaim.record.ack?.status !== "PENDING") {
    const originalAck = intentClaim.record.ack;
    return {
      ack: answerAck(
        envelope,
        initialMatch,
        "DUPLICATE",
        originalAck.rejectionCode || null,
        originalAck.status
      ),
      authorityTimestampEpochMs: intentClaim.record.authorityTimestampEpochMs ?? null,
      answerTransactionAttempts: 0,
      intentTransactionAttempts: intentClaim.transactionAttempts,
    };
  }

  const existing = initialMatch.private.answerInbox?.[envelope.questionId]?.[uid];
  let created;
  if (existing) {
    if (existing.eventId === envelope.intentId
        && !answerRecordMatches(existing, envelope, uid)) {
      const ack = answerAck(
        envelope,
        initialMatch,
        "REJECTED",
        "INTENT_REPLAY_MISMATCH"
      );
      await finalizeAnswerIntent(
        intentClaim,
        ack,
        existing.acceptedAtEpochMs ?? null
      );
      return {
        ack,
        authorityTimestampEpochMs: existing.acceptedAtEpochMs ?? null,
        answerTransactionAttempts: 0,
        intentTransactionAttempts: intentClaim.transactionAttempts,
      };
    }
    if (!answerRecordMatches(existing, envelope, uid)) {
      const preflightError = preflightAnswer(initialMatch, envelope, uid);
      const ack = answerAck(
        envelope,
        initialMatch,
        "REJECTED",
        preflightError || "ALREADY_ANSWERED"
      );
      await finalizeAnswerIntent(intentClaim, ack, existing.acceptedAtEpochMs ?? null);
      return {
        ack,
        authorityTimestampEpochMs: existing.acceptedAtEpochMs ?? null,
        answerTransactionAttempts: 0,
        intentTransactionAttempts: intentClaim.transactionAttempts,
      };
    }
    created = {
      committed: false,
      record: existing,
      reference: answerRef(envelope, uid),
      transactionAttempts: 0,
    };
  } else {
    const preflightError = preflightAnswer(initialMatch, envelope, uid);
    if (preflightError) {
      const ack = answerAck(envelope, initialMatch, "REJECTED", preflightError);
      await finalizeAnswerIntent(intentClaim, ack, null);
      return {
        ack,
        authorityTimestampEpochMs: null,
        answerTransactionAttempts: 0,
        intentTransactionAttempts: intentClaim.transactionAttempts,
      };
    }
    created = await createAnswer(envelope, uid);
  }

  const currentMatch = await readMatch(envelope.matchId);
  if (!created.record) {
    return {
      ack: answerAck(envelope, currentMatch, "REJECTED", "INTERNAL_RETRYABLE"),
      authorityTimestampEpochMs: null,
      answerTransactionAttempts: created.transactionAttempts,
      intentTransactionAttempts: intentClaim.transactionAttempts,
    };
  }
  if (!answerRecordMatches(created.record, envelope, uid)) {
    const code = created.record.eventId === envelope.intentId
      ? "INTENT_REPLAY_MISMATCH"
      : "ALREADY_ANSWERED";
    const ack = answerAck(envelope, currentMatch, "REJECTED", code);
    await finalizeAnswerIntent(
      intentClaim,
      ack,
      created.record.acceptedAtEpochMs ?? null
    );
    return {
      ack,
      authorityTimestampEpochMs: created.record.acceptedAtEpochMs ?? null,
      answerTransactionAttempts: created.transactionAttempts,
      intentTransactionAttempts: intentClaim.transactionAttempts,
    };
  }

  const decision = classifyStoredAnswer(currentMatch, envelope, uid, created.record);
  await markAnswerDecision(created.reference, decision);
  if (!decision.accepted) {
    const originalAck = answerAck(envelope, currentMatch, "REJECTED", decision.code);
    await finalizeAnswerIntent(
      intentClaim,
      originalAck,
      created.record.acceptedAtEpochMs
    );
    return {
      ack: answerAck(
        envelope,
        currentMatch,
        created.committed ? "REJECTED" : "DUPLICATE",
        decision.code,
        created.committed ? null : "REJECTED"
      ),
      authorityTimestampEpochMs: created.record.acceptedAtEpochMs,
      answerTransactionAttempts: created.transactionAttempts,
      intentTransactionAttempts: intentClaim.transactionAttempts,
    };
  }

  const isCurrentQuestion = currentMatch.private.currentQuestion?.questionId
    === envelope.questionId;
  if (isCurrentQuestion) await publishAnswered(envelope, uid);
  let ackState = currentMatch;
  if (isCurrentQuestion
      && currentMatch.private.phase === PHASE.QUESTION_OPEN
      && allActivePlayersAnswered(currentMatch.private)
      && await claimAllAnsweredClose(envelope)) {
    const acceptedTimes = Object.values(
      currentMatch.private.answerInbox?.[envelope.questionId] || {}
    ).map((answer) => answer.acceptedAtEpochMs).filter(Number.isFinite);
    const closed = await commitReconcile(
      internalCloseEnvelope(envelope),
      uid,
      Math.max(...acceptedTimes),
      currentMatch
    );
    ackState = {
      private: {
        serverSequence: closed.ack.serverSequence,
        stateVersion: closed.ack.publicStateVersion,
      },
    };
  }
  const originalAck = answerAck(
    envelope,
    ackState,
    "ACCEPTED",
    null
  );
  await finalizeAnswerIntent(
    intentClaim,
    originalAck,
    created.record.acceptedAtEpochMs
  );
  return {
    ack: answerAck(
      envelope,
      ackState,
      created.committed ? "ACCEPTED" : "DUPLICATE",
      null,
      created.committed ? null : "ACCEPTED"
    ),
    authorityTimestampEpochMs: created.record.acceptedAtEpochMs,
    answerTransactionAttempts: created.transactionAttempts,
    intentTransactionAttempts: intentClaim.transactionAttempts,
  };
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
      if (envelope.type === "forfeit") {
        const settlement = await readExplicitForfeitSettlement(envelope.matchId, uid);
        if (settlement?.status === "SETTLED") {
          const acceptedAt = settlement.forfeitCompletedAtEpochMs;
          const ack = withDiagnostics({
            intentId: envelope.intentId,
            status: "DUPLICATE",
            originalStatus: "ACCEPTED",
            serverSequence: null,
            publicStateVersion: null,
            rejectionCode: null,
            retryable: false,
          }, invocation, acceptedAt);
          logOutcome("intent", envelope, uid, ack, Boolean(request.app));
          return ack;
        }
      }
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
    const duplicate = envelope.type === "submitAnswer"
      ? null
      : existingIntentOutcome(match, envelope, uid);
    if (envelope.type === "forfeit"
        && duplicate?.originalStatus === "ACCEPTED") {
      const acceptedAt = match.private.participants[uid].forfeitedAtEpochMs || Date.now();
      await completeExplicitForfeit(envelope.matchId, uid, acceptedAt);
      await removeForfeitedPresence(envelope.matchId, uid);
      const ack = withDiagnostics(duplicate, invocation, acceptedAt);
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const activeSessionError = await preflightActiveSession(match, envelope, uid);
    if (activeSessionError) {
      const ack = withDiagnostics(
        rejection(envelope.intentId, activeSessionError, match),
        invocation
      );
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    if (duplicate) {
      const ack = withDiagnostics(duplicate, invocation);
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    if (envelope.type === "submitAnswer") {
      const committed = await commitAnswerIntent(envelope, uid, match);
      const ack = withDiagnostics(
        committed.ack,
        invocation,
        committed.authorityTimestampEpochMs,
        process.env.FUNCTIONS_EMULATOR === "true"
          ? {
            answerWrite: "PLAYER_QUESTION_CREATE_ONLY",
            answerTransactionAttempts: committed.answerTransactionAttempts,
            intentTransactionAttempts: committed.intentTransactionAttempts,
          }
          : null
      );
      logOutcome("intent", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const now = await serverTimestamp(envelope.matchId, envelope.intentId);
    const committed = await commitClientIntent(envelope, uid, now, null);
    if (envelope.type === "forfeit" && committed.status === "ACCEPTED") {
      await completeExplicitForfeit(envelope.matchId, uid, now);
      await removeForfeitedPresence(envelope.matchId, uid);
    }
    const ack = withDiagnostics(
      committed,
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
    const activeSessionError = await preflightActiveSession(match, envelope, uid);
    if (activeSessionError) {
      const ack = withDiagnostics(
        rejection(envelope.intentId, activeSessionError, match),
        invocation
      );
      logOutcome("reconcile", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const duplicate = existingIntentOutcome(match, envelope, uid);
    if (duplicate) {
      if (match.private.phase === PHASE.SETTLEMENT_PENDING) {
        await settleFinishedMatch(envelope.matchId, Date.now());
      }
      const ack = withDiagnostics(duplicate, invocation);
      logOutcome("reconcile", envelope, uid, ack, Boolean(request.app));
      return ack;
    }
    const now = await serverTimestamp(envelope.matchId, envelope.intentId);
    let committed = await commitReconcile(envelope, uid, now);
    if (committed.phase === PHASE.MATCH_FINISHED) {
      committed = await commitReconcile({
        ...envelope,
        intentId: `settlement-prepare-${envelope.matchId}`,
      }, uid, now);
    }
    if (committed.phase === PHASE.SETTLEMENT_PENDING) {
      await settleFinishedMatch(envelope.matchId, now);
      committed.phase = PHASE.SETTLED;
    }
    if (committed.phase === PHASE.MATCH_FINISHED) {
      await releaseFinishedMatchSessions(envelope.matchId);
    }
    const ack = withDiagnostics(
      committed.ack,
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

const competitivePresenceChanged = onValueWritten({
  ref: `${ROOT_PATH}/presence/{matchId}/{uid}`,
  region: DATABASE_TRIGGER_REGION,
  memory: FUNCTION_OPTIONS.memory,
  cpu: FUNCTION_OPTIONS.cpu,
  timeoutSeconds: FUNCTION_OPTIONS.timeoutSeconds,
  minInstances: FUNCTION_OPTIONS.minInstances,
  maxInstances: FUNCTION_OPTIONS.maxInstances,
}, async (event) => {
  const signal = event.data.after.val();
  if (!signal || typeof signal.connected !== "boolean") return;
  const normalizedSignal = {
    ...signal,
    status: signal.connected ? "CONNECTED" : "DISCONNECTED",
    authorityEventKey: event.time,
  };
  const { matchId, uid } = event.params;
  const reference = matchRef(matchId);
  const initial = await reference.get();
  const initialValue = initial.val();
  if (!initialValue?.private) return;
  const envelope = {
    sessionId: normalizedSignal.sessionId,
    sessionEpoch: normalizedSignal.sessionEpoch,
    matchId,
  };
  const participantError = preflightParticipant(initialValue, envelope, uid);
  if (participantError) {
    console.info("competitive_presence_ignored", { reason: participantError });
    return;
  }
  const activeSessionError = await preflightActiveSession(initialValue, envelope, uid);
  if (activeSessionError) {
    console.info("competitive_presence_ignored", { reason: activeSessionError });
    return;
  }
  const eventEpochMs = Date.parse(event.time);
  const nowEpochMs = Number.isFinite(eventEpochMs) ? eventEpochMs : Date.now();
  let computation = null;
  let firstAttempt = true;
  const transaction = await reference.transaction((current) => {
    if (current === null && firstAttempt) current = initialValue;
    firstAttempt = false;
    if (!current?.private) return;
    computation = processPresenceSignal(current, normalizedSignal, uid, nowEpochMs);
    return computation.rejectionCode === null ? computation.match : undefined;
  }, undefined, false);
  if (!transaction.committed) {
    console.info("competitive_presence_ignored", {
      reason: computation?.rejectionCode || "NO_STATE_CHANGE",
    });
  }
});

module.exports = {
  FUNCTION_OPTIONS,
  MAX_BODY_BYTES,
  competitiveIntent,
  competitivePresenceChanged,
  competitiveReconcileMatch,
  preflightActiveSession,
  preflightParticipant,
  withDiagnostics,
};
