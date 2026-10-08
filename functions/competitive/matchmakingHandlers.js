const { randomUUID } = require("node:crypto");
const { getDatabase } = require("firebase-admin/database");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { PROTOCOL_VERSION, ROOT_PATH } = require("./constants");
const { processReconcile } = require("./core");
const { FUNCTION_OPTIONS } = require("./functionOptions");
const { buildCompetitiveMatch } = require("./matchFactory");
const { validateMatchmakingIntent } = require("./matchmakingContract");
const {
  claimNextMatch,
  finalizeClaim,
  processCancelQueue,
  processJoinQueue,
  releaseFinishedMatch,
} = require("./matchmakingCore");

const MAX_MATCHES_PER_ATTEMPT = 3;

function matchmakingRef() {
  return getDatabase().ref(`${ROOT_PATH}/matchmaking`);
}

function matchRef(matchId) {
  return getDatabase().ref(`${ROOT_PATH}/matches/${matchId}`);
}

function requireUID(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication is required", {
      rejectionCode: "UNAUTHENTICATED",
    });
  }
  return uid;
}

function accountType(request) {
  return request.auth?.token?.firebase?.sign_in_provider === "anonymous"
    ? "ANONYMOUS"
    : "LINKED";
}

function rejection(intent, code) {
  return {
    intentId: intent?.intentId || "unknown",
    status: "REJECTED",
    rejectionCode: code,
    retryable: false,
  };
}

async function transactMatchmaking(processor) {
  const reference = matchmakingRef();
  const initial = await reference.get();
  const initialValue = initial.exists() ? initial.val() : null;
  let firstAttempt = true;
  let computation = null;
  const transaction = await reference.transaction((current) => {
    if (current === null && firstAttempt && initialValue !== null) current = initialValue;
    firstAttempt = false;
    computation = processor(current);
    return computation.changed ? computation.state : undefined;
  }, undefined, false);
  if (!computation) throw new Error("MATCHMAKING_TRANSACTION_NOT_EVALUATED");
  return { computation, transaction };
}

function waitingMatch(claim, nowEpochMs) {
  const match = buildCompetitiveMatch({
    matchId: claim.matchId,
    players: claim.participants.map((participant) => ({
      uid: participant.uid,
      displayName: `Player ${participant.slot + 1}`,
      sessionId: participant.sessionId,
      sessionEpoch: participant.sessionEpoch,
      assignmentTicket: participant.assignmentTicket,
    })),
    createdAtEpochMs: nowEpochMs,
  });
  const first = claim.participants[0];
  const envelope = {
    intentId: `server-create-${claim.matchId}`,
    type: "reconcile",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "competitive-v2-phase-b-server",
    sessionId: first.sessionId,
    sessionEpoch: first.sessionEpoch,
    matchId: claim.matchId,
    lastSeenServerSequence: 0,
    payload: {},
  };
  return processReconcile(match, envelope, first.uid, nowEpochMs).match;
}

function sameRoster(match, claim) {
  const participants = match?.private?.participants;
  return participants
    && Object.keys(participants).length === claim.participants.length
    && claim.participants.every((candidate) => {
      const saved = participants[candidate.uid];
      return saved
        && saved.sessionId === candidate.sessionId
        && saved.sessionEpoch === candidate.sessionEpoch
        && saved.assignmentTicket === candidate.assignmentTicket;
    });
}

async function finalizeMatch(claim) {
  const nowEpochMs = Date.now();
  const initialMatch = waitingMatch(claim, nowEpochMs);
  const transaction = await matchRef(claim.matchId).transaction((current) => {
    if (current === null) return initialMatch;
    return undefined;
  }, undefined, false);
  const saved = transaction.snapshot.val();
  if (!sameRoster(saved, claim)) throw new Error("MATCH_ID_COLLISION");

  const finalized = await transactMatchmaking((current) =>
    finalizeClaim(current, claim.matchId, Date.now())
  );
  if (!finalized.transaction.committed && !finalized.computation.finalized) {
    const snapshot = await matchmakingRef()
      .child(`private/profiles/${claim.participants[0].uid}/currentSession`)
      .get();
    if (snapshot.val()?.matchId !== claim.matchId) {
      throw new Error("MATCH_FINALIZATION_LOST");
    }
  }
}

async function recoverPendingMatches() {
  const snapshot = await matchmakingRef().child("private/pendingMatches").get();
  const pending = Object.values(snapshot.val() || {}).slice(0, MAX_MATCHES_PER_ATTEMPT);
  for (const claim of pending) await finalizeMatch(claim);
}

async function attemptMatchmaking() {
  await recoverPendingMatches();
  for (let index = 0; index < MAX_MATCHES_PER_ATTEMPT; index += 1) {
    const matchId = `match-${randomUUID()}`;
    const assignmentTickets = Array.from(
      { length: 4 },
      () => `ticket-${randomUUID()}`
    );
    const claimed = await transactMatchmaking((current) => claimNextMatch(current, {
      nowEpochMs: Date.now(),
      matchId,
      assignmentTickets,
    }));
    if (!claimed.computation.claimed) break;
    await finalizeMatch(claimed.computation.claimed);
  }
}

async function projectionFor(uid) {
  return (await matchmakingRef().child(`public/${uid}`).get()).val();
}

function ackWithProjection(original, projection) {
  if (!projection) return original;
  return {
    ...original,
    sessionId: projection.sessionId,
    sessionEpoch: projection.sessionEpoch,
    matchmakingState: projection.state,
    matchId: projection.matchId ?? null,
    assignmentTicket: projection.assignmentTicket ?? null,
  };
}

const competitiveMatchmaking = onCall(FUNCTION_OPTIONS, async (request) => {
  const uid = requireUID(request);
  const intent = request.data;
  const validationError = validateMatchmakingIntent(intent);
  if (validationError) return rejection(intent, validationError);

  try {
    let outcome;
    if (intent.type === "joinQueue") {
      outcome = await transactMatchmaking((current) => processJoinQueue(
        current,
        intent,
        uid,
        {
          nowEpochMs: Date.now(),
          generatedSessionId: `session-${randomUUID()}`,
          accountType: accountType(request),
        }
      ));
      if (outcome.computation.ack.status !== "REJECTED") await attemptMatchmaking();
    } else {
      outcome = await transactMatchmaking((current) =>
        processCancelQueue(current, intent, uid, Date.now())
      );
    }
    const result = ackWithProjection(outcome.computation.ack, await projectionFor(uid));
    console.info("competitive_matchmaking_event", {
      type: intent.type,
      status: result.status,
      rejectionCode: result.rejectionCode,
      matchmakingState: result.matchmakingState,
      matchId: result.matchId,
    });
    return result;
  } catch (error) {
    console.error("competitive_matchmaking_internal", {
      type: intent.type,
      errorName: error?.name || "Error",
    });
    throw new HttpsError("internal", "Competitive matchmaking failed", {
      rejectionCode: "INTERNAL_RETRYABLE",
    });
  }
});

async function releaseFinishedMatchSessions(matchId) {
  await transactMatchmaking((current) => releaseFinishedMatch(current, matchId, Date.now()));
}

module.exports = {
  attemptMatchmaking,
  competitiveMatchmaking,
  finalizeMatch,
  releaseFinishedMatchSessions,
};
