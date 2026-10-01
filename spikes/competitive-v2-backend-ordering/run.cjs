#!/usr/bin/env node

/*
 * Competitive v2 Phase A-1 only.
 *
 * This is a disposable local spike harness, not production backend code.
 * It deliberately refuses to run unless both Firebase emulators are present.
 */

"use strict";

const http = require("node:http");
const os = require("node:os");
const { performance } = require("node:perf_hooks");

const { initializeApp, deleteApp } = require(
  "../../functions/node_modules/firebase-admin/lib/app"
);
const { getFirestore } = require(
  "../../functions/node_modules/firebase-admin/lib/firestore"
);

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-hayaosiapp";
const MATCH_ID = "spike-match";
const PLAYERS = ["A", "B", "C", "D"];
const CONCURRENCY = PLAYERS.length;
const STARTUP_ROUNDS = 1;
const WARMUP_ROUNDS = Number(process.env.SPIKE_WARMUP_ROUNDS || 5);
const MEASURED_ROUNDS = Number(process.env.SPIKE_MEASURED_ROUNDS || 40);
const MAX_BODY_BYTES = 4096;
const MAX_ID_LENGTH = 96;
const MAX_CAS_ATTEMPTS = 20;

if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
  throw new Error("Refusing to run without FIREBASE_DATABASE_EMULATOR_HOST");
}
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Refusing to run without FIRESTORE_EMULATOR_HOST");
}

const app = initializeApp(
  {
    projectId: PROJECT_ID,
    databaseURL: `https://${PROJECT_ID}-default-rtdb.firebaseio.com`,
  },
  "competitive-v2-ordering-spike"
);
const firestore = getFirestore(app);

function rtdbUrl(matchId) {
  const host = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  const namespace = `${PROJECT_ID}-default-rtdb`;
  return `http://${host}/competitiveV2Spike/candidateA/${matchId}.json?ns=${namespace}`;
}

function rtdbHeaders(extra = {}) {
  return {
    authorization: "Bearer owner",
    ...extra,
  };
}

function initialMatchState() {
  return {
    serverSequence: 0,
    players: Object.fromEntries(
      PLAYERS.map((playerId) => [
        playerId,
        {
          sessionId: `session-${playerId}`,
          sessionEpoch: 1,
        },
      ])
    ),
    processedEvents: {},
    playerBuzzes: {},
  };
}

function validateIntent(intent) {
  if (!intent || typeof intent !== "object" || Array.isArray(intent)) {
    return "MALFORMED_REQUEST";
  }

  const requiredStrings = ["matchId", "playerId", "eventId", "sessionId"];
  for (const field of requiredStrings) {
    if (
      typeof intent[field] !== "string" ||
      intent[field].length === 0 ||
      intent[field].length > MAX_ID_LENGTH
    ) {
      return "MALFORMED_REQUEST";
    }
  }

  const safeIdentifier = /^[A-Za-z0-9_-]+$/;
  if (
    !safeIdentifier.test(intent.matchId) ||
    !safeIdentifier.test(intent.playerId) ||
    !safeIdentifier.test(intent.eventId) ||
    !safeIdentifier.test(intent.sessionId)
  ) {
    return "MALFORMED_REQUEST";
  }

  if (!Number.isSafeInteger(intent.sessionEpoch) || intent.sessionEpoch < 1) {
    return "MALFORMED_REQUEST";
  }
  if (intent.buzz !== true) {
    return "MALFORMED_REQUEST";
  }

  return null;
}

function inspectState(state, intent) {
  if (!state) {
    return { status: "rejected", code: "UNKNOWN_MATCH" };
  }

  const player = state.players?.[intent.playerId];
  if (!player) {
    return { status: "rejected", code: "UNKNOWN_PLAYER" };
  }
  if (
    player.sessionId !== intent.sessionId ||
    player.sessionEpoch !== intent.sessionEpoch
  ) {
    return { status: "rejected", code: "STALE_SESSION" };
  }

  const priorEvent = state.processedEvents?.[intent.eventId];
  if (priorEvent) {
    return {
      status: "duplicate",
      code: "DUPLICATE_EVENT",
      accepted: priorEvent.accepted,
      serverSequence: priorEvent.serverSequence,
    };
  }

  const priorPlayerBuzz = state.playerBuzzes?.[intent.playerId];
  if (priorPlayerBuzz) {
    return {
      status: "rejected",
      code: "DUPLICATE_PLAYER_BUZZ",
      observedSequence: state.serverSequence,
    };
  }

  return { status: "ready" };
}

function acceptedState(state, intent, receivedAtEpochMs) {
  const serverSequence = (state.serverSequence || 0) + 1;
  const event = {
    accepted: true,
    playerId: intent.playerId,
    eventId: intent.eventId,
    sessionId: intent.sessionId,
    sessionEpoch: intent.sessionEpoch,
    serverSequence,
    receivedAtEpochMs,
  };

  return {
    state: {
      ...state,
      serverSequence,
      processedEvents: {
        ...(state.processedEvents || {}),
        [intent.eventId]: event,
      },
      playerBuzzes: {
        ...(state.playerBuzzes || {}),
        [intent.playerId]: {
          eventId: intent.eventId,
          serverSequence,
        },
      },
    },
    event,
  };
}

function finalizeDecision(decision, t1, attempts) {
  const t2 = performance.now();
  return {
    ...decision,
    attempts,
    receivedAt: new Date(
      performance.timeOrigin + t1
    ).toISOString(),
    orderingConfirmedAt: new Date(
      performance.timeOrigin + t2
    ).toISOString(),
    timing: { t1, t2 },
  };
}

async function orderWithRtdb(intent, t1) {
  const validationError = validateIntent(intent);
  if (validationError) {
    return finalizeDecision(
      { status: "rejected", code: validationError },
      t1,
      0
    );
  }

  const receivedAtEpochMs = Date.now();
  let attempts = 0;
  const url = rtdbUrl(intent.matchId);

  while (attempts < MAX_CAS_ATTEMPTS) {
    attempts += 1;
    const readResponse = await fetch(url, {
      headers: rtdbHeaders({ "x-firebase-etag": "true" }),
    });
    if (!readResponse.ok) {
      throw new Error(`RTDB read failed: HTTP ${readResponse.status}`);
    }

    const state = await readResponse.json();
    const inspection = inspectState(state, intent);
    if (inspection.status !== "ready") {
      return finalizeDecision(inspection, t1, attempts);
    }

    const accepted = acceptedState(state, intent, receivedAtEpochMs);
    const etag = readResponse.headers.get("etag");
    if (!etag) {
      throw new Error("RTDB emulator did not return an ETag");
    }

    const writeResponse = await fetch(url, {
      method: "PUT",
      headers: rtdbHeaders({
        "content-type": "application/json",
        "if-match": etag,
      }),
      body: JSON.stringify(accepted.state),
    });

    if (writeResponse.status === 412) {
      continue;
    }
    if (!writeResponse.ok) {
      throw new Error(`RTDB CAS failed: HTTP ${writeResponse.status}`);
    }

    return finalizeDecision(
      {
        status: "accepted",
        accepted: true,
        serverSequence: accepted.event.serverSequence,
      },
      t1,
      attempts
    );
  }

  throw new Error(`RTDB CAS exceeded ${MAX_CAS_ATTEMPTS} attempts`);
}

async function orderWithFirestore(intent, t1) {
  const validationError = validateIntent(intent);
  if (validationError) {
    return finalizeDecision(
      { status: "rejected", code: validationError },
      t1,
      0
    );
  }

  const receivedAtEpochMs = Date.now();
  const reference = firestore
    .collection("competitiveV2SpikeCandidateB")
    .doc(intent.matchId);
  let attempts = 0;

  const decision = await firestore.runTransaction(
    async (transaction) => {
      attempts += 1;
      const snapshot = await transaction.get(reference);
      const state = snapshot.exists ? snapshot.data() : null;
      const inspection = inspectState(state, intent);
      if (inspection.status !== "ready") {
        return inspection;
      }

      const accepted = acceptedState(state, intent, receivedAtEpochMs);
      transaction.set(reference, accepted.state);
      return {
        status: "accepted",
        accepted: true,
        serverSequence: accepted.event.serverSequence,
      };
    },
    { maxAttempts: 10 }
  );

  return finalizeDecision(decision, t1, attempts);
}

class PerMatchSequencer {
  constructor() {
    this.matches = new Map();
    this.tails = new Map();
  }

  resetMatch(matchId) {
    this.matches.set(matchId, initialMatchState());
    this.tails.set(matchId, Promise.resolve());
  }

  order(intent, t1) {
    const validationError = validateIntent(intent);
    if (validationError) {
      return Promise.resolve(
        finalizeDecision(
          { status: "rejected", code: validationError },
          t1,
          0
        )
      );
    }

    const previousTail = this.tails.get(intent.matchId) || Promise.resolve();
    let resolveResult;
    const result = new Promise((resolve) => {
      resolveResult = resolve;
    });

    const nextTail = previousTail.then(() => {
      const state = this.matches.get(intent.matchId) || null;
      const inspection = inspectState(state, intent);
      if (inspection.status !== "ready") {
        resolveResult(finalizeDecision(inspection, t1, 1));
        return;
      }

      const accepted = acceptedState(state, intent, Date.now());
      this.matches.set(intent.matchId, accepted.state);
      resolveResult(
        finalizeDecision(
          {
            status: "accepted",
            accepted: true,
            serverSequence: accepted.event.serverSequence,
          },
          t1,
          1
        )
      );
    });

    this.tails.set(
      intent.matchId,
      nextTail.catch(() => undefined)
    );
    return result;
  }
}

const sequencer = new PerMatchSequencer();

async function resetCandidate(candidate, matchId = MATCH_ID) {
  if (candidate === "a") {
    const response = await fetch(rtdbUrl(matchId), {
      method: "PUT",
      headers: rtdbHeaders({ "content-type": "application/json" }),
      body: JSON.stringify(initialMatchState()),
    });
    if (!response.ok) {
      throw new Error(`RTDB reset failed: HTTP ${response.status}`);
    }
    return;
  }
  if (candidate === "b") {
    await firestore
      .collection("competitiveV2SpikeCandidateB")
      .doc(matchId)
      .set(initialMatchState());
    return;
  }
  if (candidate === "c") {
    sequencer.resetMatch(matchId);
    return;
  }
  throw new Error(`Unknown candidate: ${candidate}`);
}

async function readRequestBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw new Error("REQUEST_TOO_LARGE");
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJson(response, statusCode, body) {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function startServer() {
  const server = http.createServer(async (request, response) => {
    const t1 = performance.now();
    try {
      if (request.method !== "POST") {
        sendJson(response, 405, { error: "METHOD_NOT_ALLOWED" });
        return;
      }

      const candidate = request.url?.replace(/^\//, "");
      const intent = await readRequestBody(request);
      let result;
      if (candidate === "a") {
        result = await orderWithRtdb(intent, t1);
      } else if (candidate === "b") {
        result = await orderWithFirestore(intent, t1);
      } else if (candidate === "c") {
        result = await sequencer.order(intent, t1);
      } else {
        sendJson(response, 404, { error: "UNKNOWN_CANDIDATE" });
        return;
      }
      sendJson(response, 200, result);
    } catch (error) {
      const code = error.message === "REQUEST_TOO_LARGE" ? 413 : 500;
      sendJson(response, code, {
        error: error.message || "INTERNAL_ERROR",
      });
    }
  });

  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function makeIntent(playerId, eventId, matchId = MATCH_ID) {
  return {
    matchId,
    playerId,
    eventId,
    sessionId: `session-${playerId}`,
    sessionEpoch: 1,
    buzz: true,
  };
}

async function sendIntent(origin, candidate, intent) {
  const t0 = performance.now();
  const response = await fetch(`${origin}/${candidate}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(intent),
  });
  const body = await response.json();
  const t3 = performance.now();
  if (!response.ok) {
    throw new Error(
      `${candidate} returned HTTP ${response.status}: ${JSON.stringify(body)}`
    );
  }

  return {
    ...body,
    timing: {
      ...body.timing,
      t0,
      t3,
      t1ToT2Ms: body.timing.t2 - body.timing.t1,
      t0ToT2Ms: body.timing.t2 - t0,
      t0ToT3Ms: t3 - t0,
    },
  };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`ASSERTION_FAILED: ${message}`);
  }
}

function assertConcurrentRound(results, candidate, roundName) {
  assert(results.length === CONCURRENCY, `${candidate}/${roundName}: result count`);
  assert(
    results.every((result) => result.status === "accepted"),
    `${candidate}/${roundName}: all unique players must be accepted; got ${JSON.stringify(
      results.map((result) => ({
        status: result.status,
        code: result.code,
        serverSequence: result.serverSequence,
        observedSequence: result.observedSequence,
        attempts: result.attempts,
      }))
    )}`
  );
  const sequences = results
    .map((result) => result.serverSequence)
    .sort((left, right) => left - right);
  assert(
    JSON.stringify(sequences) === JSON.stringify([1, 2, 3, 4]),
    `${candidate}/${roundName}: expected unique sequences 1...4, got ${sequences}`
  );
}

async function runConcurrentRound(origin, candidate, roundName) {
  await resetCandidate(candidate);
  const results = await Promise.all(
    PLAYERS.map((playerId) =>
      sendIntent(
        origin,
        candidate,
        makeIntent(playerId, `${candidate}-${roundName}-${playerId}`)
      )
    )
  );
  assertConcurrentRound(results, candidate, roundName);
  return results;
}

function percentile(values, percentileValue) {
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.max(
    0,
    Math.min(sorted.length - 1, Math.ceil(percentileValue * sorted.length) - 1)
  );
  return sorted[index];
}

function rounded(value) {
  return Math.round(value * 1000) / 1000;
}

function metricSummary(results, field) {
  const values = results.map((result) => result.timing[field]);
  return {
    min: rounded(Math.min(...values)),
    p50: rounded(percentile(values, 0.5)),
    p95: rounded(percentile(values, 0.95)),
    max: rounded(Math.max(...values)),
  };
}

function summarizeLatency(results) {
  return {
    t1ToT2Ms: metricSummary(results, "t1ToT2Ms"),
    t0ToT2Ms: metricSummary(results, "t0ToT2Ms"),
    t0ToT3Ms: metricSummary(results, "t0ToT3Ms"),
  };
}

async function runFunctionalChecks(origin, candidate) {
  await resetCandidate(candidate);

  const firstIntent = makeIntent("A", `${candidate}-functional-original`);
  const accepted = await sendIntent(origin, candidate, firstIntent);
  const duplicateEvent = await sendIntent(origin, candidate, firstIntent);
  const duplicatePlayer = await sendIntent(
    origin,
    candidate,
    makeIntent("A", `${candidate}-functional-second-event`)
  );
  const staleIntent = {
    ...makeIntent("B", `${candidate}-functional-stale`),
    sessionEpoch: 2,
  };
  const staleSession = await sendIntent(origin, candidate, staleIntent);
  const malformed = await sendIntent(origin, candidate, {
    matchId: MATCH_ID,
    playerId: "B",
    eventId: `${candidate}-functional-malformed`,
    buzz: true,
  });
  const oversizedField = await sendIntent(origin, candidate, {
    ...makeIntent("B", "x".repeat(MAX_ID_LENGTH + 1)),
  });
  const unknownMatch = await sendIntent(
    origin,
    candidate,
    makeIntent("B", `${candidate}-functional-unknown`, "missing-match")
  );

  assert(accepted.status === "accepted", `${candidate}: initial accepted`);
  assert(
    duplicateEvent.status === "duplicate" &&
      duplicateEvent.serverSequence === accepted.serverSequence,
    `${candidate}: event replay must reuse original sequence`
  );
  assert(
    duplicatePlayer.code === "DUPLICATE_PLAYER_BUZZ",
    `${candidate}: duplicate player buzz rejected`
  );
  assert(staleSession.code === "STALE_SESSION", `${candidate}: stale session rejected`);
  assert(malformed.code === "MALFORMED_REQUEST", `${candidate}: malformed rejected`);
  assert(
    oversizedField.code === "MALFORMED_REQUEST",
    `${candidate}: oversized field rejected`
  );
  assert(unknownMatch.code === "UNKNOWN_MATCH", `${candidate}: unknown match rejected`);

  return {
    accepted: {
      status: accepted.status,
      serverSequence: accepted.serverSequence,
    },
    duplicateEvent: {
      status: duplicateEvent.status,
      code: duplicateEvent.code,
      serverSequence: duplicateEvent.serverSequence,
    },
    duplicatePlayer: {
      status: duplicatePlayer.status,
      code: duplicatePlayer.code,
    },
    staleSession: {
      status: staleSession.status,
      code: staleSession.code,
    },
    malformed: { status: malformed.status, code: malformed.code },
    oversizedField: {
      status: oversizedField.status,
      code: oversizedField.code,
    },
    unknownMatch: {
      status: unknownMatch.status,
      code: unknownMatch.code,
    },
  };
}

async function benchmarkCandidate(origin, candidate) {
  const startupResults = await runConcurrentRound(origin, candidate, "startup-0");

  for (let round = 0; round < WARMUP_ROUNDS; round += 1) {
    await runConcurrentRound(origin, candidate, `warmup-${round}`);
  }

  const measuredResults = [];
  for (let round = 0; round < MEASURED_ROUNDS; round += 1) {
    measuredResults.push(
      ...(await runConcurrentRound(origin, candidate, `measured-${round}`))
    );
  }

  const totalAttempts = measuredResults.reduce(
    (total, result) => total + result.attempts,
    0
  );
  const totalRetries = measuredResults.reduce(
    (total, result) => total + Math.max(0, result.attempts - 1),
    0
  );

  return {
    orderingAuthority:
      candidate === "a"
        ? "RTDB ETag compare-and-set loop on one match root"
        : candidate === "b"
          ? "Firestore transaction on one match document"
          : "one in-process serialized queue per match",
    requestCounts: {
      startupMeasured: startupResults.length,
      warmupExcluded: WARMUP_ROUNDS * CONCURRENCY,
      warmMeasured: measuredResults.length,
    },
    startupLikeLatency: summarizeLatency(startupResults),
    warmLatency: summarizeLatency(measuredResults),
    contention: {
      transactionCallbackAttempts: totalAttempts,
      retries: totalRetries,
      retryRatePerIntent: rounded(totalRetries / measuredResults.length),
    },
    allMeasuredRoundsHadUniqueSequences: true,
    functionalChecks: await runFunctionalChecks(origin, candidate),
  };
}

async function demonstrateSequencerScalingRisk() {
  const authorityOne = new PerMatchSequencer();
  const authorityTwo = new PerMatchSequencer();
  authorityOne.resetMatch(MATCH_ID);
  authorityTwo.resetMatch(MATCH_ID);

  const first = await authorityOne.order(
    makeIntent("A", "split-authority-a"),
    performance.now()
  );
  const second = await authorityTwo.order(
    makeIntent("B", "split-authority-b"),
    performance.now()
  );

  return {
    authorityOneSequence: first.serverSequence,
    authorityTwoSequence: second.serverSequence,
    duplicateSequenceObserved:
      first.serverSequence === second.serverSequence,
    conclusion:
      "Horizontal scaling requires match routing plus durable ownership/fencing; two independent authorities are invalid.",
  };
}

async function closeServer(server) {
  await new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

async function main() {
  const server = await startServer();
  const address = server.address();
  const origin = `http://127.0.0.1:${address.port}`;

  try {
    const results = {};
    for (const candidate of ["a", "b", "c"]) {
      results[candidate] = await benchmarkCandidate(origin, candidate);
    }

    const report = {
      generatedAt: new Date().toISOString(),
      purpose: "Competitive v2 Phase A-1 per-match ordering spike",
      environment: {
        projectId: PROJECT_ID,
        platform: `${os.platform()} ${os.release()} ${os.arch()}`,
        node: process.version,
        database: `RTDB Emulator ${process.env.FIREBASE_DATABASE_EMULATOR_HOST}`,
        firestore: `Firestore Emulator ${process.env.FIRESTORE_EMULATOR_HOST}`,
        testOrigin: "Local HTTP loopback on the same Mac/process",
        actualCloud: false,
        cloudColdStartMeasured: false,
        concurrency: CONCURRENCY,
        startupRounds: STARTUP_ROUNDS,
        warmupRounds: WARMUP_ROUNDS,
        measuredRounds: MEASURED_ROUNDS,
        percentileMethod: "nearest-rank",
      },
      semanticNote:
        "The spike orders all four unique buzz events as 1...4. Production state rules would grant the answer right only to the first and reject later buzzes after BUZZ_LOCKED.",
      candidates: results,
      candidateCScalingNegativeControl:
        await demonstrateSequencerScalingRisk(),
    };

    console.log("SPIKE_RESULT_JSON_START");
    console.log(JSON.stringify(report, null, 2));
    console.log("SPIKE_RESULT_JSON_END");
  } finally {
    await closeServer(server);
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
