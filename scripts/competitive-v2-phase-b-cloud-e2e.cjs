#!/usr/bin/env node

"use strict";

const path = require("node:path");
const { createRequire } = require("node:module");
const { performance } = require("node:perf_hooks");
const { randomUUID } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");

const { buildTestMatch } = require("../functions/competitive/testMatchFactory");
const {
  PHASE,
  PROTOCOL_VERSION,
  REGION,
  ROOT_PATH,
} = require("../functions/competitive/constants");

const PROJECT_ID = "hayaosiapp";
const DATABASE_HOST = "hayaosiapp-default-rtdb.asia-southeast1.firebasedatabase.app";
const EXECUTION_CONFIRMATION = "ALLOW_ISOLATED_COMPETITIVE_V2_PHASE_B_CLOUD_E2E";
const CLIENT_BUILD = "competitive-v2-phase-b-cloud-e2e";
const DEFAULT_TIMEOUT_MS = 30_000;
const TEST_UID_ENV_NAMES = Object.freeze([
  "COMPETITIVE_TEST_UID_1",
  "COMPETITIVE_TEST_UID_2",
  "COMPETITIVE_TEST_UID_3",
  "COMPETITIVE_TEST_UID_4",
]);
const MATCHMAKING_ROOT = ROOT_PATH + "/matchmaking";

function assert(condition, message) {
  if (!condition) throw new Error("ASSERTION_FAILED: " + message);
}

function requiredEnvironment(environment, name) {
  const value = environment[name];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error("Missing required environment variable: " + name);
  }
  return value.trim();
}

function safeFirebaseKey(value, name) {
  if (typeof value !== "string"
      || value.length < 1
      || value.length > 128
      || /[.#$\[\]/]/.test(value)) {
    throw new Error(name + " is not a safe Firebase key");
  }
  return value;
}

function parseTestUIDs(environment) {
  const values = TEST_UID_ENV_NAMES.map((name) =>
    safeFirebaseKey(requiredEnvironment(environment, name), name)
  );
  if (new Set(values).size !== values.length) {
    throw new Error("The four Competitive test UIDs must be unique");
  }
  return values;
}

function executionConfiguration(environment = process.env) {
  if (environment.COMPETITIVE_V2_PHASE_B_E2E_ALLOW_PRODUCTION !== EXECUTION_CONFIRMATION) {
    throw new Error("Production execution confirmation is missing");
  }
  const projectId = requiredEnvironment(
    environment,
    "COMPETITIVE_V2_PHASE_B_E2E_PROJECT_ID"
  );
  if (projectId !== PROJECT_ID) throw new Error("Project must be " + PROJECT_ID);

  const databaseURL = new URL(requiredEnvironment(
    environment,
    "COMPETITIVE_V2_PHASE_B_E2E_DATABASE_URL"
  ));
  if (databaseURL.protocol !== "https:" || databaseURL.hostname !== DATABASE_HOST) {
    throw new Error("Database must be " + DATABASE_HOST);
  }
  const authDomain = requiredEnvironment(
    environment,
    "COMPETITIVE_V2_PHASE_B_E2E_AUTH_DOMAIN"
  );
  if (authDomain !== PROJECT_ID + ".firebaseapp.com") {
    throw new Error("Auth domain must be " + PROJECT_ID + ".firebaseapp.com");
  }
  return {
    projectId,
    databaseURL: databaseURL.toString(),
    apiKey: requiredEnvironment(environment, "COMPETITIVE_V2_PHASE_B_E2E_API_KEY"),
    authDomain,
    testUIDs: parseTestUIDs(environment),
  };
}

function reviewPlan() {
  return {
    mode: "review-only",
    productionReadPerformed: false,
    productionWritePerformed: false,
    projectId: PROJECT_ID,
    region: REGION,
    functions: [
      "competitiveMatchmaking",
      "competitiveIntent",
      "competitiveReconcileMatch",
    ],
    userCount: 4,
    flow: [
      "isolation gate",
      "representative security and retry checks",
      "queue to exactly one release-test match",
      "abort before countdown and verify session release",
      "queue to exactly one core-bridge match",
      "joinMatch, ready, COUNTDOWN, QUESTION_OPEN",
      "exact-path cleanup and readback",
    ],
    runtimeInputs: [
      "impersonation Application Default Credentials",
      "COMPETITIVE_V2_PHASE_B_E2E_API_KEY",
      "COMPETITIVE_V2_PHASE_B_E2E_AUTH_DOMAIN",
      "COMPETITIVE_V2_PHASE_B_E2E_DATABASE_URL",
      "COMPETITIVE_V2_PHASE_B_E2E_PROJECT_ID",
      "COMPETITIVE_TEST_UID_1 through COMPETITIVE_TEST_UID_4",
      "COMPETITIVE_V2_PHASE_B_E2E_ALLOW_PRODUCTION",
    ],
    safeguards: [
      "--execute or --phase-a-smoke and exact confirmation are both required",
      "the global queue and pending-match roots must be empty before writes",
      "all four Auth users must already exist",
      "UIDs and credentials are never included in reports",
      "only exact test UID, sentinel, match, pending-match, and clock paths are removed",
      "rooms and Friend Battle paths are never read or written",
    ],
    timing: {
      "T0": "immediately before the fourth joinQueue request",
      "T1": "Function ingress; recorded only if the deployed ack exposes it",
      "T2": "atomic claim completion; recorded only if the deployed ack exposes it",
      "T3": "fourth joinQueue HTTP ack available",
      "T4": "all four clients have observed the same match assignment projection",
    },
  };
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitFor(predicate, description, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await sleep(25);
  }
  throw new Error("Timed out waiting for " + description);
}

async function waitUntilEpoch(epochMs, extraMs = 250) {
  const delayMs = epochMs + extraMs - Date.now();
  if (delayMs > 0) await sleep(delayMs);
}

function rounded(value) {
  return Number(value.toFixed(3));
}

function makeRunId() {
  return "e2e-b-" + Date.now() + "-" + randomUUID();
}

function makeSmokeMatchId() {
  return "e2e-b-smoke-" + Date.now() + "-" + randomUUID();
}

function makeSentinelId(runId) {
  return "sentinel-" + runId;
}

function matchmakingIntent(type, intentId, overrides = {}) {
  return {
    intentId,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: CLIENT_BUILD,
    payload: {},
    ...overrides,
  };
}

function competitiveEnvelope(player, matchId, type, intentId, overrides = {}) {
  return {
    intentId,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: CLIENT_BUILD,
    sessionId: player.sessionId,
    sessionEpoch: player.sessionEpoch,
    matchId,
    lastSeenServerSequence: player.matchTracker?.latest?.serverSequence ?? 0,
    payload: {},
    ...overrides,
  };
}

function isAssignmentProjection(value, matchId = null) {
  return value
    && ["MATCH_FOUND", "WAITING_PLAYERS"].includes(value.state)
    && typeof value.matchId === "string"
    && (matchId === null || value.matchId === matchId)
    && typeof value.assignmentTicket === "string";
}

function assignmentMeasurement(startedAtMonotonicMs, ackAtMonotonicMs, observations, ack) {
  const assigned = observations.map((playerObservations) =>
    playerObservations.find((item) =>
      item.observedAtMonotonicMs >= startedAtMonotonicMs
      && isAssignmentProjection(item.value, ack.matchId)
    )
  );
  assert(assigned.every(Boolean), "all four clients must observe the same match assignment");
  const t4 = Math.max(...assigned.map((item) => item.observedAtMonotonicMs));
  const exactT1ToT2 = ack.timing?.t1ToT2Ms;
  return {
    t0ToT3Ms: rounded(ackAtMonotonicMs - startedAtMonotonicMs),
    t0ToT4Ms: rounded(t4 - startedAtMonotonicMs),
    t1ToT2Ms: Number.isFinite(exactT1ToT2) ? rounded(exactT1ToT2) : null,
    serverTimingAvailability: Number.isFinite(exactT1ToT2)
      ? "ACK_EXPOSED"
      : "NOT_EXPOSED_BY_CURRENT_FUNCTION",
  };
}

function cleanupTargets({ testUIDs, sentinelId, matchIds, pendingMatchIds }) {
  assert(Array.isArray(testUIDs) && testUIDs.length === 4, "cleanup requires four test UIDs");
  testUIDs.forEach((uid, index) => safeFirebaseKey(uid, "cleanup UID " + (index + 1)));
  safeFirebaseKey(sentinelId, "sentinel ID");
  assert(sentinelId.startsWith("sentinel-e2e-b-"), "sentinel must be run-scoped");

  const safeMatches = [...new Set(matchIds)];
  const safePending = [...new Set(pendingMatchIds)];
  assert(safeMatches.length <= 4, "cleanup match count exceeds the test boundary");
  assert(safePending.length <= 4, "cleanup pending-match count exceeds the test boundary");
  safeMatches.forEach((matchId, index) => safeFirebaseKey(matchId, "match ID " + (index + 1)));
  safePending.forEach((matchId, index) =>
    safeFirebaseKey(matchId, "pending match ID " + (index + 1))
  );

  return [
    ...testUIDs.flatMap((uid) => [
      MATCHMAKING_ROOT + "/private/queue/" + uid,
      MATCHMAKING_ROOT + "/private/profiles/" + uid,
      MATCHMAKING_ROOT + "/public/" + uid,
    ]),
    MATCHMAKING_ROOT + "/private/profiles/" + sentinelId,
    ...safePending.map((matchId) =>
      MATCHMAKING_ROOT + "/private/pendingMatches/" + matchId
    ),
    ...safeMatches.flatMap((matchId) => [
      ROOT_PATH + "/matches/" + matchId,
      ROOT_PATH + "/clocks/" + matchId,
    ]),
  ];
}

function loadSDKs() {
  const clientApp = require("firebase/app");
  const clientAuth = require("firebase/auth");
  const clientDatabase = require("firebase/database");
  const clientFunctions = require("firebase/functions");
  const functionsRequire = createRequire(path.resolve(__dirname, "../functions/package.json"));
  return {
    clientApp,
    clientAuth,
    clientDatabase,
    clientFunctions,
    adminApp: functionsRequire("firebase-admin/app"),
    adminAuth: functionsRequire("firebase-admin/auth"),
    adminDatabase: functionsRequire("firebase-admin/database"),
  };
}

async function createRuntime(config) {
  const sdk = loadSDKs();
  const adminApplication = sdk.adminApp.initializeApp({
    credential: sdk.adminApp.applicationDefault(),
    databaseURL: config.databaseURL,
    projectId: config.projectId,
  }, "competitive-phase-b-admin-" + randomUUID());
  const adminAuthentication = sdk.adminAuth.getAuth(adminApplication);
  const adminRTDB = sdk.adminDatabase.getDatabase(adminApplication);
  const players = [];
  const unsubscribers = [];

  try {
    await Promise.all(config.testUIDs.map((uid) => adminAuthentication.getUser(uid)));
    for (const [index, uid] of config.testUIDs.entries()) {
      const application = sdk.clientApp.initializeApp({
        apiKey: config.apiKey,
        authDomain: config.authDomain,
        databaseURL: config.databaseURL,
        projectId: config.projectId,
      }, "competitive-phase-b-client-" + index + "-" + randomUUID());
      const authentication = sdk.clientAuth.getAuth(application);
      const customToken = await adminAuthentication.createCustomToken(uid);
      const credential = await sdk.clientAuth.signInWithCustomToken(
        authentication,
        customToken
      );
      assert(credential.user.uid === uid, "test user " + (index + 1) + " UID mismatch");
      const database = sdk.clientDatabase.getDatabase(application);
      const functions = sdk.clientFunctions.getFunctions(application, REGION);
      players.push({
        index,
        uid,
        application,
        authentication,
        database,
        matchmaking: sdk.clientFunctions.httpsCallable(
          functions,
          "competitiveMatchmaking"
        ),
        intent: sdk.clientFunctions.httpsCallable(functions, "competitiveIntent"),
        reconcile: sdk.clientFunctions.httpsCallable(
          functions,
          "competitiveReconcileMatch"
        ),
        projectionTracker: null,
        matchTracker: null,
        sessionId: null,
        sessionEpoch: null,
        assignmentTicket: null,
      });
    }
  } catch (error) {
    await closeRuntime({ sdk, adminApplication, players, unsubscribers });
    throw error;
  }
  return {
    sdk,
    adminApplication,
    adminAuthentication,
    adminRTDB,
    players,
    unsubscribers,
    discoveredMatchIds: new Set(),
    observedPending: new Map(),
  };
}

async function closeRuntime(runtime) {
  for (const unsubscribe of runtime.unsubscribers.splice(0)) unsubscribe();
  for (const player of runtime.players) {
    runtime.sdk.clientDatabase.goOffline(player.database);
    await runtime.sdk.clientAuth.signOut(player.authentication);
    await runtime.sdk.clientApp.deleteApp(player.application);
  }
  await runtime.sdk.adminApp.deleteApp(runtime.adminApplication);
}

function createClientTracker(runtime, player, relativePath) {
  const observations = [];
  let latest = null;
  let cancellationError = null;
  const unsubscribe = runtime.sdk.clientDatabase.onValue(
    runtime.sdk.clientDatabase.ref(player.database, relativePath),
    (snapshot) => {
      latest = snapshot.val();
      observations.push({
        value: latest,
        observedAtMonotonicMs: performance.now(),
      });
    },
    (error) => {
      cancellationError = error;
    }
  );
  runtime.unsubscribers.push(unsubscribe);
  return {
    get latest() { return latest; },
    get cancellationError() { return cancellationError; },
    observations,
  };
}

function startProjectionTrackers(runtime) {
  for (const player of runtime.players) {
    player.projectionTracker = createClientTracker(
      runtime,
      player,
      MATCHMAKING_ROOT + "/public/" + player.uid
    );
  }
}

function startPendingTracker(runtime) {
  const reference = runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/pendingMatches"
  );
  const listener = reference.on("child_added", (snapshot) => {
    runtime.observedPending.set(snapshot.key, snapshot.val());
  });
  runtime.unsubscribers.push(() => reference.off("child_added", listener));
}

function startMatchTrackers(runtime, matchId) {
  for (const player of runtime.players) {
    player.matchTracker = createClientTracker(
      runtime,
      player,
      ROOT_PATH + "/matches/" + matchId + "/public"
    );
  }
}

async function waitForProjection(player, predicate, description) {
  return waitFor(() => {
    assert(!player.projectionTracker.cancellationError, description + ": listener cancelled");
    return predicate(player.projectionTracker.latest) && player.projectionTracker.latest;
  }, description);
}

async function waitForAllMatchTrackers(runtime, predicate, description) {
  await waitFor(() => runtime.players.every((player) => {
    assert(!player.matchTracker.cancellationError, description + ": listener cancelled");
    return player.matchTracker.latest && predicate(player.matchTracker.latest);
  }), description);
  const states = runtime.players.map((player) => player.matchTracker.latest);
  const canonical = JSON.stringify(states[0]);
  assert(
    states.every((state) => JSON.stringify(state) === canonical),
    description + ": four public match projections must match"
  );
  return states[0];
}

async function expectCallableError(action, expectedCode, description) {
  try {
    await action();
    throw new Error(description + " unexpectedly succeeded");
  } catch (error) {
    const code = String(error?.code || "").toLowerCase();
    assert(code.includes(expectedCode.toLowerCase()), description + " returned " + code);
  }
}

async function expectPermissionDenied(action, description) {
  try {
    await action();
    throw new Error(description + " unexpectedly succeeded");
  } catch (error) {
    const value = String(error?.code || error?.message || "").toLowerCase();
    assert(value.includes("permission"), description + " must be permission denied");
  }
}

async function invoke(callable, payload) {
  return (await callable(payload)).data;
}

function assertAck(ack, status, rejectionCode, description) {
  assert(ack?.status === status, description + ": unexpected status");
  assert(
    (ack?.rejectionCode ?? null) === rejectionCode,
    description + ": unexpected rejection"
  );
}

async function assertIsolation(runtime, config, sentinelId) {
  const exactPaths = config.testUIDs.flatMap((uid) => [
    MATCHMAKING_ROOT + "/private/queue/" + uid,
    MATCHMAKING_ROOT + "/private/profiles/" + uid,
    MATCHMAKING_ROOT + "/public/" + uid,
  ]).concat([MATCHMAKING_ROOT + "/private/profiles/" + sentinelId]);
  const snapshots = await Promise.all(
    exactPaths.map((entry) => runtime.adminRTDB.ref(entry).get())
  );
  assert(snapshots.every((snapshot) => !snapshot.exists()),
    "one or more exact test UID matchmaking paths already exist");

  const [queue, pending] = await Promise.all([
    runtime.adminRTDB.ref(MATCHMAKING_ROOT + "/private/queue").get(),
    runtime.adminRTDB.ref(MATCHMAKING_ROOT + "/private/pendingMatches").get(),
  ]);
  assert(!queue.exists(), "global matchmaking queue is not empty");
  assert(!pending.exists(), "pending matchmaking state is not empty");
}

async function assertUnauthenticatedRejected(runtime, config) {
  const application = runtime.sdk.clientApp.initializeApp({
    apiKey: config.apiKey,
    authDomain: config.authDomain,
    databaseURL: config.databaseURL,
    projectId: config.projectId,
  }, "competitive-phase-b-unauthenticated-" + randomUUID());
  try {
    const functions = runtime.sdk.clientFunctions.getFunctions(application, REGION);
    const callable = runtime.sdk.clientFunctions.httpsCallable(
      functions,
      "competitiveMatchmaking"
    );
    await expectCallableError(
      () => callable(matchmakingIntent("joinQueue", "unauthenticated-" + randomUUID())),
      "unauthenticated",
      "unauthenticated joinQueue"
    );
  } finally {
    await runtime.sdk.clientApp.deleteApp(application);
  }
}

async function assertInvalidClientAuthority(player) {
  const attempts = [
    { label: "client UID", extra: { uid: "client-selected" } },
    { label: "client MMR", extra: { payload: { mmr: 9999 } } },
    { label: "client Rank", extra: { payload: { rank: "MASTER" } } },
    { label: "client matchId", extra: { payload: { matchId: "client-match" } } },
  ];
  for (const attempt of attempts) {
    const ack = await invoke(player.matchmaking, matchmakingIntent(
      "joinQueue",
      "invalid-" + randomUUID(),
      attempt.extra
    ));
    assertAck(ack, "REJECTED", "INVALID_PAYLOAD", attempt.label);
  }
}

async function runRetryAndCancellationChecks(runtime) {
  const first = runtime.players[0];
  const other = runtime.players[1];
  const stableId = "join-stable-" + randomUUID();
  const stableIntent = matchmakingIntent("joinQueue", stableId);
  const accepted = await invoke(first.matchmaking, stableIntent);
  assertAck(accepted, "ACCEPTED", null, "first joinQueue");
  await waitForProjection(
    first,
    (value) => value?.state === "QUEUED",
    "first QUEUED projection"
  );

  const retry = await invoke(first.matchmaking, stableIntent);
  assertAck(retry, "DUPLICATE", null, "joinQueue retry");
  assert(retry.originalStatus === "ACCEPTED", "joinQueue retry must preserve acceptance");
  assert(retry.sessionId === accepted.sessionId, "joinQueue retry changed sessionId");
  assert(retry.sessionEpoch === accepted.sessionEpoch, "joinQueue retry changed sessionEpoch");

  const replayMismatch = await invoke(first.matchmaking, matchmakingIntent(
    "cancelQueue",
    stableId,
    {
      sessionId: accepted.sessionId,
      sessionEpoch: accepted.sessionEpoch,
    }
  ));
  assertAck(
    replayMismatch,
    "REJECTED",
    "INTENT_REPLAY_MISMATCH",
    "payload-changing intent replay"
  );

  const second = await invoke(first.matchmaking, matchmakingIntent(
    "joinQueue",
    "join-second-" + randomUUID()
  ));
  assertAck(second, "ACCEPTED", null, "second joinQueue");
  assert(second.sessionEpoch === accepted.sessionEpoch + 1,
    "second joinQueue must fence the previous session");
  const queue = (await runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/queue/" + first.uid
  ).get()).val();
  assert(queue?.sessionId === second.sessionId, "second joinQueue must converge to one queue entry");

  const staleSession = await invoke(first.matchmaking, matchmakingIntent(
    "cancelQueue",
    "cancel-stale-session-" + randomUUID(),
    {
      sessionId: "stale-session-" + randomUUID(),
      sessionEpoch: second.sessionEpoch,
    }
  ));
  assertAck(
    staleSession,
    "REJECTED",
    "STALE_SESSION_EPOCH",
    "stale session cancellation"
  );

  const staleEpoch = await invoke(first.matchmaking, matchmakingIntent(
    "cancelQueue",
    "cancel-stale-epoch-" + randomUUID(),
    {
      sessionId: second.sessionId,
      sessionEpoch: accepted.sessionEpoch,
    }
  ));
  assertAck(
    staleEpoch,
    "REJECTED",
    "STALE_SESSION_EPOCH",
    "stale epoch cancellation"
  );

  const otherPlayer = await invoke(other.matchmaking, matchmakingIntent(
    "cancelQueue",
    "cancel-other-" + randomUUID(),
    {
      sessionId: second.sessionId,
      sessionEpoch: second.sessionEpoch,
    }
  ));
  assertAck(otherPlayer, "REJECTED", "SESSION_NOT_ACTIVE", "other-player cancellation");
  const afterOther = (await runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/queue/" + first.uid
  ).get()).val();
  assert(afterOther?.sessionId === second.sessionId,
    "other player cancellation changed the queued session");

  const cancelId = "cancel-stable-" + randomUUID();
  const cancelIntent = matchmakingIntent("cancelQueue", cancelId, {
    sessionId: second.sessionId,
    sessionEpoch: second.sessionEpoch,
  });
  const cancelled = await invoke(first.matchmaking, cancelIntent);
  assertAck(cancelled, "ACCEPTED", null, "cancelQueue");
  const cancelRetry = await invoke(first.matchmaking, cancelIntent);
  assertAck(cancelRetry, "DUPLICATE", null, "cancelQueue retry");
  await waitForProjection(
    first,
    (value) => value?.state === "NOT_QUEUED",
    "cancelled projection"
  );
}

function updatePlayerAssignments(runtime, projections) {
  for (const player of runtime.players) {
    const projection = projections.get(player.uid);
    assert(typeof projection.sessionId === "string" && projection.sessionId.length > 0,
      "Server must assign a sessionId");
    assert(Number.isSafeInteger(projection.sessionEpoch) && projection.sessionEpoch >= 1,
      "Server must assign a positive sessionEpoch");
    assert(typeof projection.assignmentTicket === "string"
      && projection.assignmentTicket.length > 0,
      "Server must assign an assignmentTicket");
    player.sessionId = projection.sessionId;
    player.sessionEpoch = projection.sessionEpoch;
    player.assignmentTicket = projection.assignmentTicket;
  }
}

async function createMatchFromQueue(runtime, label) {
  const observationsBefore = runtime.players.map(
    (player) => player.projectionTracker.observations.length
  );
  let fourthStart = null;
  let fourthAckAt = null;
  let fourthAck = null;

  for (const [index, player] of runtime.players.entries()) {
    const payload = matchmakingIntent("joinQueue", label + "-join-" + randomUUID());
    if (index === runtime.players.length - 1) fourthStart = performance.now();
    const ack = await invoke(player.matchmaking, payload);
    if (index === runtime.players.length - 1) {
      fourthAckAt = performance.now();
      fourthAck = ack;
    }
    assertAck(ack, "ACCEPTED", null, label + " joinQueue " + (index + 1));
    if (index < runtime.players.length - 1) {
      await waitForProjection(
        player,
        (value) => value?.state === "QUEUED",
        label + " QUEUED " + (index + 1)
      );
    }
  }

  const fourthProjection = await waitForProjection(
    runtime.players[3],
    (value) => isAssignmentProjection(value),
    label + " fourth assignment"
  );
  const matchId = fourthAck.matchId || fourthProjection.matchId;
  safeFirebaseKey(matchId, label + " matchId");
  runtime.discoveredMatchIds.add(matchId);

  const projections = new Map();
  for (const player of runtime.players) {
    const projection = await waitForProjection(
      player,
      (value) => isAssignmentProjection(value, matchId),
      label + " assignment " + (player.index + 1)
    );
    projections.set(player.uid, projection);
    const newObservations = player.projectionTracker.observations.slice(
      observationsBefore[player.index]
    );
    assert(newObservations.some((item) => item.value?.state === "QUEUED"),
      label + ": each player must observe QUEUED before assignment");
    assert(newObservations.some((item) =>
      item.value?.state === "MATCH_FOUND" && item.value?.matchId === matchId
    ), label + ": each player must observe MATCH_FOUND");
  }
  updatePlayerAssignments(runtime, projections);

  await waitFor(() => runtime.observedPending.has(matchId),
    label + " pending manifest observation", 5_000);
  const manifest = runtime.observedPending.get(matchId);
  const expectedUIDs = new Set(runtime.players.map((player) => player.uid));
  assert(Array.isArray(manifest?.participants), label + ": pending manifest missing participants");
  assert(manifest.participants.length === 4, label + ": pending manifest must have four players");
  assert(manifest.participants.every((item) => expectedUIDs.has(item.uid)),
    label + ": pending manifest contains an unexpected player");

  await assertMatchCorrectness(runtime, matchId, manifest);
  const measurement = assignmentMeasurement(
    fourthStart,
    fourthAckAt,
    runtime.players.map((player) => player.projectionTracker.observations),
    { ...fourthAck, matchId }
  );
  return { matchId, manifest, measurement };
}

async function assertMatchCorrectness(runtime, matchId, manifest) {
  const [privateMatch, pending] = await Promise.all([
    runtime.adminRTDB.ref(ROOT_PATH + "/matches/" + matchId + "/private").get(),
    runtime.adminRTDB.ref(
      MATCHMAKING_ROOT + "/private/pendingMatches/" + matchId
    ).get(),
  ]);
  assert(privateMatch.exists(), "actual match must exist");
  assert(!pending.exists(), "pending manifest must be finalized and removed");
  const match = privateMatch.val();
  assert(match.phase === PHASE.WAITING_PLAYERS, "created match must be WAITING_PLAYERS");
  const expectedUIDs = new Set(runtime.players.map((player) => player.uid));
  assert(Object.keys(match.participants || {}).length === 4,
    "actual match must contain exactly four participants");
  assert(Object.keys(match.participants).every((uid) => expectedUIDs.has(uid)),
    "actual match contains an unexpected participant");

  for (const participant of manifest.participants) {
    const saved = match.participants[participant.uid];
    assert(saved?.sessionId === participant.sessionId,
      "pending and actual match sessionId mismatch");
    assert(saved?.sessionEpoch === participant.sessionEpoch,
      "pending and actual match sessionEpoch mismatch");
    assert(saved?.assignmentTicket === participant.assignmentTicket,
      "pending and actual match ticket mismatch");
  }

  for (const player of runtime.players) {
    const [queue, profile] = await Promise.all([
      runtime.adminRTDB.ref(
        MATCHMAKING_ROOT + "/private/queue/" + player.uid
      ).get(),
      runtime.adminRTDB.ref(
        MATCHMAKING_ROOT + "/private/profiles/" + player.uid + "/currentSession"
      ).get(),
    ]);
    assert(!queue.exists(), "claimed player must be removed from queue");
    assert(profile.val()?.matchId === matchId, "profile active match mismatch");
  }
}

async function assertPostMatchSecurity(runtime, matchId) {
  const first = runtime.players[0];
  const cancel = await invoke(first.matchmaking, matchmakingIntent(
    "cancelQueue",
    "cancel-after-match-" + randomUUID(),
    {
      sessionId: first.sessionId,
      sessionEpoch: first.sessionEpoch,
    }
  ));
  assertAck(cancel, "REJECTED", "MATCH_ALREADY_ASSIGNED", "cancel after match");

  const newQueue = await invoke(first.matchmaking, matchmakingIntent(
    "joinQueue",
    "join-after-match-" + randomUUID()
  ));
  assertAck(newQueue, "REJECTED", "ACTIVE_MATCH_EXISTS", "queue after match");

  const other = runtime.players[1];
  await expectPermissionDenied(
    () => runtime.sdk.clientDatabase.get(runtime.sdk.clientDatabase.ref(
      other.database,
      MATCHMAKING_ROOT + "/public/" + first.uid
    )),
    "other public projection read"
  );
  await expectPermissionDenied(
    () => runtime.sdk.clientDatabase.get(runtime.sdk.clientDatabase.ref(
      first.database,
      MATCHMAKING_ROOT + "/private/profiles/" + first.uid
    )),
    "private profile read"
  );
  await expectPermissionDenied(
    () => runtime.sdk.clientDatabase.get(runtime.sdk.clientDatabase.ref(
      first.database,
      MATCHMAKING_ROOT + "/private/queue/" + first.uid
    )),
    "private queue read"
  );
  await expectPermissionDenied(
    () => runtime.sdk.clientDatabase.set(runtime.sdk.clientDatabase.ref(
      first.database,
      ROOT_PATH + "/matches/" + matchId + "/private/participants/"
        + first.uid + "/ready"
    ), true),
    "participant direct write"
  );
}

async function createSentinel(runtime, sentinelId, runId) {
  const value = {
    uid: sentinelId,
    marker: runId,
    currentSession: {
      state: "WAITING_PLAYERS",
      sessionId: "sentinel-session-" + runId,
      sessionEpoch: 1,
      matchId: "sentinel-other-match-" + runId,
    },
  };
  await runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/profiles/" + sentinelId
  ).set(value);
  return value;
}

async function runSessionRelease(runtime, matchId, sentinelId, sentinelValue) {
  startMatchTrackers(runtime, matchId);
  await waitForAllMatchTrackers(
    runtime,
    (value) => value.phase === PHASE.WAITING_PLAYERS,
    "release match WAITING_PLAYERS"
  );
  const leaving = runtime.players[0];
  const leave = await invoke(leaving.intent, competitiveEnvelope(
    leaving,
    matchId,
    "leave",
    "release-leave-" + randomUUID()
  ));
  assertAck(leave, "ACCEPTED", null, "release match leave");
  await waitForAllMatchTrackers(
    runtime,
    (value) => value.phase === PHASE.MATCH_FINISHED,
    "release match MATCH_FINISHED"
  );
  const reconcilePlayer = runtime.players[1];
  const reconcile = await invoke(reconcilePlayer.reconcile, competitiveEnvelope(
    reconcilePlayer,
    matchId,
    "reconcile",
    "release-reconcile-" + randomUUID()
  ));
  assertAck(reconcile, "ACCEPTED", null, "release reconcile");

  for (const player of runtime.players) {
    await waitForProjection(
      player,
      (value) => value?.state === "NOT_QUEUED",
      "released projection " + (player.index + 1)
    );
    const [profile, queue] = await Promise.all([
      runtime.adminRTDB.ref(
        MATCHMAKING_ROOT + "/private/profiles/" + player.uid + "/currentSession"
      ).get(),
      runtime.adminRTDB.ref(
        MATCHMAKING_ROOT + "/private/queue/" + player.uid
      ).get(),
    ]);
    assert(profile.val()?.state === "FINISHED", "released session must be FINISHED");
    assert(profile.val()?.matchId === null, "released session must clear active match");
    assert(!queue.exists(), "released session must not remain queued");
  }
  const sentinel = (await runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/profiles/" + sentinelId
  ).get()).val();
  assert(isDeepStrictEqual(sentinel, sentinelValue),
    "non-target sentinel session was changed");
}

async function runCoreBridge(runtime, matchId) {
  startMatchTrackers(runtime, matchId);
  await waitForAllMatchTrackers(
    runtime,
    (value) => value.phase === PHASE.WAITING_PLAYERS,
    "core bridge WAITING_PLAYERS"
  );
  for (const player of runtime.players) {
    const joined = await invoke(player.intent, competitiveEnvelope(
      player,
      matchId,
      "joinMatch",
      "bridge-join-" + randomUUID(),
      { payload: { assignmentTicket: player.assignmentTicket } }
    ));
    assertAck(joined, "ACCEPTED", null, "core bridge joinMatch");
  }
  for (const player of runtime.players) {
    const ready = await invoke(player.intent, competitiveEnvelope(
      player,
      matchId,
      "ready",
      "bridge-ready-" + randomUUID()
    ));
    assertAck(ready, "ACCEPTED", null, "core bridge ready");
  }
  const countdown = await waitForAllMatchTrackers(
    runtime,
    (value) => value.phase === PHASE.COUNTDOWN,
    "core bridge COUNTDOWN"
  );
  await waitUntilEpoch(countdown.countdownEndsAtEpochMs, 250);
  const reconcile = await invoke(runtime.players[0].reconcile, competitiveEnvelope(
    runtime.players[0],
    matchId,
    "reconcile",
    "bridge-countdown-" + randomUUID()
  ));
  assertAck(reconcile, "ACCEPTED", null, "core bridge countdown reconcile");
  await waitForAllMatchTrackers(
    runtime,
    (value) => value.phase === PHASE.QUESTION_OPEN
      && value.currentQuestionIndex === 0,
    "core bridge QUESTION_OPEN"
  );
}

async function discoverCleanupResources(runtime, config) {
  const matchIds = new Set(runtime.discoveredMatchIds);
  for (const uid of config.testUIDs) {
    const profile = (await runtime.adminRTDB.ref(
      MATCHMAKING_ROOT + "/private/profiles/" + uid + "/currentSession"
    ).get()).val();
    if (typeof profile?.matchId === "string") matchIds.add(profile.matchId);
  }

  const pendingMatchIds = new Set();
  const pending = (await runtime.adminRTDB.ref(
    MATCHMAKING_ROOT + "/private/pendingMatches"
  ).get()).val() || {};
  const allowed = new Set(config.testUIDs);
  for (const [matchId, manifest] of Object.entries(pending)) {
    const participants = Array.isArray(manifest?.participants)
      ? manifest.participants.map((item) => item.uid)
      : [];
    if (participants.length === 0 || !participants.some((uid) => allowed.has(uid))) continue;
    assert(participants.every((uid) => allowed.has(uid)),
      "unsafe pending match contains both test and non-test users");
    pendingMatchIds.add(matchId);
    matchIds.add(matchId);
  }
  return {
    matchIds: [...matchIds],
    pendingMatchIds: [...pendingMatchIds],
  };
}

async function cleanup(runtime, config, sentinelId) {
  for (const unsubscribe of runtime.unsubscribers.splice(0)) unsubscribe();
  const resources = await discoverCleanupResources(runtime, config);
  const targets = cleanupTargets({
    testUIDs: config.testUIDs,
    sentinelId,
    matchIds: resources.matchIds,
    pendingMatchIds: resources.pendingMatchIds,
  });
  for (const target of targets) await runtime.adminRTDB.ref(target).remove();
  const snapshots = await Promise.all(
    targets.map((target) => runtime.adminRTDB.ref(target).get())
  );
  assert(snapshots.every((snapshot) => !snapshot.exists()),
    "one or more exact cleanup targets still exist");
  return {
    confirmed: true,
    queueEntries: 4,
    profiles: 4,
    publicProjections: 4,
    sentinels: 1,
    pendingMatches: resources.pendingMatchIds.length,
    matches: resources.matchIds.length,
    clocks: resources.matchIds.length,
  };
}

async function executePhaseB(config) {
  const runId = makeRunId();
  const sentinelId = makeSentinelId(runId);
  let runtime = null;
  let cleanupArmed = false;
  let cleanupReport = null;
  let report = null;

  try {
    runtime = await createRuntime(config);
    await assertIsolation(runtime, config, sentinelId);
    cleanupArmed = true;
    startProjectionTrackers(runtime);
    startPendingTracker(runtime);
    await assertUnauthenticatedRejected(runtime, config);
    await assertInvalidClientAuthority(runtime.players[0]);
    await runRetryAndCancellationChecks(runtime);

    const sentinelValue = await createSentinel(runtime, sentinelId, runId);
    const releaseMatch = await createMatchFromQueue(runtime, "release");
    await assertPostMatchSecurity(runtime, releaseMatch.matchId);
    await runSessionRelease(
      runtime,
      releaseMatch.matchId,
      sentinelId,
      sentinelValue
    );

    const bridgeMatch = await createMatchFromQueue(runtime, "bridge");
    await runCoreBridge(runtime, bridgeMatch.matchId);

    report = {
      status: "passed",
      projectId: config.projectId,
      region: REGION,
      reusedExistingAuthUsers: 4,
      authUserValuesLogged: false,
      matchesCreated: 2,
      assignmentLatency: {
        releaseMatch: releaseMatch.measurement,
        bridgeMatch: bridgeMatch.measurement,
      },
      assertions: {
        isolationGate: true,
        unauthenticatedRejected: true,
        clientAuthorityFieldsRejected: true,
        retryAndIdempotency: true,
        fourHumansExactlyOneMatch: true,
        queueAndManifestConsistency: true,
        ownProjectionTransitions: true,
        privateAndCrossUserReadsDenied: true,
        directParticipantWriteDenied: true,
        sessionRelease: true,
        nonTargetSentinelUnchanged: true,
        phaseA2CoreBridgeToQuestionOpen: true,
      },
    };
  } finally {
    try {
      if (runtime && cleanupArmed) {
        cleanupReport = await cleanup(runtime, config, sentinelId);
      }
    } finally {
      if (runtime) await closeRuntime(runtime);
    }
  }
  report.cleanup = cleanupReport;
  return report;
}

async function executePhaseASmoke(config) {
  const matchId = makeSmokeMatchId();
  let runtime = null;
  let created = false;
  let cleaned = false;
  try {
    runtime = await createRuntime(config);
    const existing = await runtime.adminRTDB.ref(
      ROOT_PATH + "/matches/" + matchId
    ).get();
    assert(!existing.exists(), "smoke match path unexpectedly exists");
    const players = runtime.players.map((player, index) => {
      player.sessionId = "smoke-session-" + randomUUID();
      player.sessionEpoch = 1;
      player.assignmentTicket = "smoke-ticket-" + randomUUID();
      return {
        uid: player.uid,
        displayName: "Cloud Smoke " + (index + 1),
        sessionId: player.sessionId,
        sessionEpoch: player.sessionEpoch,
        assignmentTicket: player.assignmentTicket,
      };
    });
    const match = buildTestMatch({
      matchId,
      players,
      createdAtEpochMs: Date.now(),
      countdownDurationMs: 500,
      questionDurationMs: 5_000,
      resultDurationMs: 250,
    });
    created = true;
    await runtime.adminRTDB.ref(ROOT_PATH + "/matches/" + matchId).set(match);
    startMatchTrackers(runtime, matchId);
    const reconcile = await invoke(runtime.players[0].reconcile, competitiveEnvelope(
      runtime.players[0],
      matchId,
      "reconcile",
      "phase-a-smoke-" + randomUUID()
    ));
    assertAck(reconcile, "ACCEPTED", null, "Phase A-2 reconcile smoke");
    await waitForAllMatchTrackers(
      runtime,
      (value) => value.phase === PHASE.WAITING_PLAYERS,
      "Phase A-2 WAITING_PLAYERS smoke"
    );
    await expectPermissionDenied(
      () => runtime.sdk.clientDatabase.get(runtime.sdk.clientDatabase.ref(
        runtime.players[0].database,
        ROOT_PATH + "/matches/" + matchId + "/private"
      )),
      "Phase A-2 private read"
    );
  } finally {
    try {
      if (runtime && created) {
        for (const unsubscribe of runtime.unsubscribers.splice(0)) unsubscribe();
        await runtime.adminRTDB.ref(ROOT_PATH + "/matches/" + matchId).remove();
        await runtime.adminRTDB.ref(ROOT_PATH + "/clocks/" + matchId).remove();
        const [match, clock] = await Promise.all([
          runtime.adminRTDB.ref(ROOT_PATH + "/matches/" + matchId).get(),
          runtime.adminRTDB.ref(ROOT_PATH + "/clocks/" + matchId).get(),
        ]);
        cleaned = !match.exists() && !clock.exists();
      }
    } finally {
      if (runtime) await closeRuntime(runtime);
    }
  }
  assert(cleaned, "Phase A-2 smoke cleanup was not confirmed");
  return {
    status: "passed",
    projectId: config.projectId,
    region: REGION,
    assertions: {
      representativeReconcile: true,
      waitingPlayersProjection: true,
      privateReadDenied: true,
    },
    cleanup: { confirmed: true, matches: 1, clocks: 1 },
  };
}

function safeErrorMessage(error) {
  return String(error?.message || error || "Unknown error")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[REDACTED_TOKEN]")
    .replace(/AIza[0-9A-Za-z_-]{35}/g, "[REDACTED_API_KEY]")
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com/g,
      "[REDACTED_SERVICE_ACCOUNT]");
}

async function main() {
  if (process.argv.includes("--review")) {
    process.stdout.write(JSON.stringify(reviewPlan(), null, 2) + "\n");
    return;
  }
  const execute = process.argv.includes("--execute");
  const smoke = process.argv.includes("--phase-a-smoke");
  if (execute === smoke) {
    throw new Error(
      "Refusing to run. Select exactly one of --review, --phase-a-smoke, or --execute"
    );
  }
  const config = executionConfiguration();
  const result = smoke
    ? await executePhaseASmoke(config)
    : await executePhaseB(config);
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(safeErrorMessage(error) + "\n");
    process.exitCode = 1;
  });
}

module.exports = {
  DATABASE_HOST,
  EXECUTION_CONFIRMATION,
  PROJECT_ID,
  TEST_UID_ENV_NAMES,
  assignmentMeasurement,
  cleanupTargets,
  executionConfiguration,
  isAssignmentProjection,
  makeRunId,
  makeSentinelId,
  matchmakingIntent,
  parseTestUIDs,
  reviewPlan,
  safeErrorMessage,
};
