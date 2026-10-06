#!/usr/bin/env node

"use strict";

const path = require("node:path");
const { createRequire } = require("node:module");
const { performance } = require("node:perf_hooks");
const { randomUUID } = require("node:crypto");

const { buildTestMatch } = require("../functions/competitive/testMatchFactory");
const {
  PHASE,
  PROTOCOL_VERSION,
  QUESTION_COUNT,
  REGION,
  ROOT_PATH,
} = require("../functions/competitive/constants");

const PROJECT_ID = "hayaosiapp";
const DATABASE_HOST = "hayaosiapp-default-rtdb.asia-southeast1.firebasedatabase.app";
const EXECUTION_CONFIRMATION = "ALLOW_ISOLATED_COMPETITIVE_V2_CLOUD_E2E";
const CLIENT_BUILD = "competitive-v2-cloud-e2e";
const DEFAULT_TIMEOUT_MS = 30_000;

function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION_FAILED: ${message}`);
}

function requiredEnvironment(environment, name) {
  const value = environment[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function safeFirebaseKey(value, name) {
  if (typeof value !== "string"
      || value.length < 1
      || value.length > 128
      || /[.#$\[\]/]/.test(value)) {
    throw new Error(`${name} is not a safe Firebase key`);
  }
  return value;
}

function parseTestUIDs(rawValue) {
  const values = rawValue.split(",").map((value) => value.trim()).filter(Boolean);
  if (values.length !== 4) {
    throw new Error("COMPETITIVE_V2_E2E_TEST_UIDS must contain exactly four UIDs");
  }
  values.forEach((value, index) => safeFirebaseKey(value, `test UID ${index + 1}`));
  if (new Set(values).size !== values.length) {
    throw new Error("COMPETITIVE_V2_E2E_TEST_UIDS must contain four unique UIDs");
  }
  return values;
}

function executionConfiguration(environment = process.env) {
  if (environment.COMPETITIVE_V2_E2E_ALLOW_PRODUCTION !== EXECUTION_CONFIRMATION) {
    throw new Error("Production execution confirmation is missing");
  }
  const projectId = requiredEnvironment(environment, "COMPETITIVE_V2_E2E_PROJECT_ID");
  if (projectId !== PROJECT_ID) throw new Error(`Project must be ${PROJECT_ID}`);

  const databaseURL = new URL(requiredEnvironment(
    environment,
    "COMPETITIVE_V2_E2E_DATABASE_URL"
  ));
  if (databaseURL.protocol !== "https:" || databaseURL.hostname !== DATABASE_HOST) {
    throw new Error(`Database must be ${DATABASE_HOST}`);
  }
  const authDomain = requiredEnvironment(environment, "COMPETITIVE_V2_E2E_AUTH_DOMAIN");
  if (authDomain !== `${PROJECT_ID}.firebaseapp.com`) {
    throw new Error(`Auth domain must be ${PROJECT_ID}.firebaseapp.com`);
  }

  return {
    projectId,
    databaseURL: databaseURL.toString(),
    apiKey: requiredEnvironment(environment, "COMPETITIVE_V2_E2E_API_KEY"),
    authDomain,
    testUIDs: parseTestUIDs(requiredEnvironment(
      environment,
      "COMPETITIVE_V2_E2E_TEST_UIDS"
    )),
  };
}

function reviewPlan() {
  return {
    mode: "review-only",
    productionWritePerformed: false,
    projectId: PROJECT_ID,
    region: REGION,
    namespace: `${ROOT_PATH}/matches/<random-test-match-id>`,
    playerCount: 4,
    questionCount: QUESTION_COUNT,
    functions: ["competitiveIntent", "competitiveReconcileMatch"],
    deployCommands: [
      "firebase deploy --project hayaosiapp --only database",
      "firebase deploy --project hayaosiapp --only functions:competitiveIntent,functions:competitiveReconcileMatch",
    ],
    credentialInputs: [
      "Application Default Credentials for Admin SDK",
      "COMPETITIVE_V2_E2E_API_KEY",
      "COMPETITIVE_V2_E2E_AUTH_DOMAIN",
      "COMPETITIVE_V2_E2E_DATABASE_URL",
      "COMPETITIVE_V2_E2E_PROJECT_ID",
      "COMPETITIVE_V2_E2E_TEST_UIDS",
    ],
    safeguards: [
      "--execute and exact production confirmation are both required",
      "project, auth domain, database host, player count, and UID uniqueness are validated",
      "tokens and credentials are never printed",
      "only the generated matchId and its clock path are removed during cleanup",
      "Friend Battle rooms are never read or written",
    ],
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
  throw new Error(`Timed out waiting for ${description}`);
}

async function waitUntilEpoch(epochMs, extraMs = 250) {
  const delayMs = epochMs + extraMs - Date.now();
  if (delayMs > 0) await sleep(delayMs);
}

function nearestRank(values, ratio) {
  const ordered = [...values].sort((left, right) => left - right);
  return ordered[Math.max(0, Math.ceil(ordered.length * ratio) - 1)];
}

function rounded(value) {
  return Number(value.toFixed(3));
}

function metricSummary(metrics, key) {
  const values = metrics.map((metric) => metric[key]).filter(Number.isFinite);
  if (values.length === 0) return { count: 0 };
  return {
    count: values.length,
    min: rounded(Math.min(...values)),
    p50: rounded(nearestRank(values, 0.50)),
    p95: rounded(nearestRank(values, 0.95)),
    max: rounded(Math.max(...values)),
  };
}

function latencySummary(metrics) {
  return {
    t1ToT2Ms: metricSummary(metrics, "t1ToT2Ms"),
    t0ToT3Ms: metricSummary(metrics, "t0ToT3Ms"),
    t0ToT4Ms: metricSummary(metrics, "t0ToT4Ms"),
  };
}

function questionStrategy(questionIndex) {
  if (questionIndex === 0) return "ALL_CORRECT_ORDERED";
  if (questionIndex === 1) return "WRONG_THEN_CORRECT";
  if (questionIndex === 2) return "DEADLINE_WITH_UNANSWERED";
  if (questionIndex === 3) return "SECURITY_AND_IDEMPOTENCY";
  return "ALL_CORRECT_ORDERED";
}

function makeMatchId() {
  return `e2e-a2-${Date.now()}-${randomUUID()}`;
}

function envelope(player, matchId, type, eventId, overrides = {}) {
  return {
    intentId: eventId,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: CLIENT_BUILD,
    sessionId: player.sessionId,
    sessionEpoch: player.sessionEpoch,
    matchId,
    lastSeenServerSequence: player.tracker.latest?.serverSequence ?? 0,
    payload: {},
    ...overrides,
  };
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

function createTracker(database, matchId, clientDatabase) {
  const observations = [];
  let latest = null;
  let cancellationError = null;
  const unsubscribe = clientDatabase.onValue(
    clientDatabase.ref(database, `${ROOT_PATH}/matches/${matchId}/public`),
    (snapshot) => {
      const state = snapshot.val();
      if (!state) return;
      latest = state;
      observations.push({ state, observedAtMonotonicMs: performance.now() });
    },
    (error) => {
      cancellationError = error;
    }
  );
  return {
    get latest() { return latest; },
    get cancellationError() { return cancellationError; },
    observations,
    unsubscribe,
  };
}

async function waitForAllTrackers(players, predicate, description) {
  await waitFor(() => players.every((player) => {
    assert(!player.tracker.cancellationError, `${description}: listener cancelled`);
    return player.tracker.latest && predicate(player.tracker.latest);
  }), description);
}

function firstObservationAtVersion(tracker, stateVersion) {
  return tracker.observations.find(
    (observation) => observation.state.stateVersion >= stateVersion
  );
}

async function timedCallable(players, callable, payload, projectionVersion = null) {
  const t0MonotonicMs = performance.now();
  const result = await callable(payload);
  const t3MonotonicMs = performance.now();
  const ack = result.data;
  let t4MonotonicMs = null;
  if (Number.isSafeInteger(projectionVersion ?? ack.publicStateVersion)) {
    const version = projectionVersion ?? ack.publicStateVersion;
    await waitForAllTrackers(
      players,
      (state) => state.stateVersion >= version,
      `public projection stateVersion ${version}`
    );
    const observations = players.map((player) => firstObservationAtVersion(
      player.tracker,
      version
    ));
    assert(observations.every(Boolean), `all clients must observe stateVersion ${version}`);
    t4MonotonicMs = Math.max(...observations.map(
      (observation) => observation.observedAtMonotonicMs
    ));
  }
  return {
    ack,
    metric: {
      t1ToT2Ms: ack.timing?.t1ToT2Ms,
      t0ToT3Ms: t3MonotonicMs - t0MonotonicMs,
      t0ToT4Ms: t4MonotonicMs === null ? null : t4MonotonicMs - t0MonotonicMs,
      authorityTimestampEpochMs: ack.timing?.authorityTimestampEpochMs,
      instanceId: ack.runtime?.instanceId,
      coldInstanceInvocation: ack.runtime?.coldInstanceInvocation,
      instanceAgeAtT1Ms: ack.runtime?.instanceAgeAtT1Ms,
    },
  };
}

async function createRuntime(config, matchId) {
  const sdk = loadSDKs();
  const adminName = `competitive-cloud-e2e-admin-${randomUUID()}`;
  const adminApplication = sdk.adminApp.initializeApp({
    credential: sdk.adminApp.applicationDefault(),
    databaseURL: config.databaseURL,
    projectId: config.projectId,
  }, adminName);
  const adminAuthentication = sdk.adminAuth.getAuth(adminApplication);
  const adminRTDB = sdk.adminDatabase.getDatabase(adminApplication);
  const players = [];

  try {
    // createCustomToken sign-in can create a missing Auth user. Require all four
    // explicitly approved test users to exist before any client sign-in occurs.
    await Promise.all(config.testUIDs.map((uid) => adminAuthentication.getUser(uid)));
    for (const [index, uid] of config.testUIDs.entries()) {
      const application = sdk.clientApp.initializeApp({
        apiKey: config.apiKey,
        authDomain: config.authDomain,
        databaseURL: config.databaseURL,
        projectId: config.projectId,
      }, `competitive-cloud-e2e-client-${index}-${randomUUID()}`);
      const authentication = sdk.clientAuth.getAuth(application);
      const customToken = await adminAuthentication.createCustomToken(uid);
      const credential = await sdk.clientAuth.signInWithCustomToken(authentication, customToken);
      assert(credential.user.uid === uid, `test user ${index + 1} UID mismatch`);
      const database = sdk.clientDatabase.getDatabase(application);
      const functions = sdk.clientFunctions.getFunctions(application, REGION);
      players.push({
        uid,
        application,
        authentication,
        database,
        intent: sdk.clientFunctions.httpsCallable(functions, "competitiveIntent"),
        reconcile: sdk.clientFunctions.httpsCallable(functions, "competitiveReconcileMatch"),
        sessionId: `cloud-session-${randomUUID()}`,
        sessionEpoch: 1,
        assignmentTicket: `cloud-ticket-${randomUUID()}`,
        tracker: null,
      });
    }
  } catch (error) {
    await closeRuntime({ sdk, adminApplication, players });
    throw error;
  }

  return { sdk, adminApplication, adminRTDB, players };
}

async function closeRuntime(runtime) {
  for (const player of runtime.players) {
    player.tracker?.unsubscribe();
    runtime.sdk.clientDatabase.goOffline(player.database);
    await runtime.sdk.clientAuth.signOut(player.authentication);
    await runtime.sdk.clientApp.deleteApp(player.application);
  }
  await runtime.sdk.adminApp.deleteApp(runtime.adminApplication);
}

async function assertPrivateDenied(player, matchId, clientDatabase) {
  try {
    await clientDatabase.get(clientDatabase.ref(
      player.database,
      `${ROOT_PATH}/matches/${matchId}/private`
    ));
    throw new Error("private state read unexpectedly succeeded");
  } catch (error) {
    const code = String(error?.code || error?.message || "").toLowerCase();
    assert(code.includes("permission"), "private state read must fail with permission denied");
  }
}

function assertScoreDeltas(result, expected, label) {
  for (const [uid, score] of expected.entries()) {
    assert(result.scoreDeltas?.[uid] === score, `${label}: unexpected score for a player`);
  }
}

async function readPrivate(runtime, matchId) {
  return (await runtime.adminRTDB.ref(
    `${ROOT_PATH}/matches/${matchId}/private`
  ).get()).val();
}

async function callIntent(runtime, player, event) {
  return timedCallable(runtime.players, player.intent, event);
}

async function callReconcile(runtime, player, matchId, suffix) {
  const event = envelope(
    player,
    matchId,
    "reconcile",
    `reconcile-${suffix}-${randomUUID()}`
  );
  return timedCallable(runtime.players, player.reconcile, event);
}

async function submitAnswer(runtime, matchId, player, question, stateVersion, answerId, eventId) {
  return callIntent(runtime, player, envelope(
    player,
    matchId,
    "submitAnswer",
    eventId,
    {
      questionId: question.questionId,
      stateVersion,
      payload: { answerId },
    }
  ));
}

async function waitForPhase(runtime, phase, questionIndex, description) {
  await waitForAllTrackers(
    runtime.players,
    (state) => state.phase === phase
      && (questionIndex === null || state.currentQuestionIndex === questionIndex),
    description
  );
  const states = runtime.players.map((player) => player.tracker.latest);
  const canonical = JSON.stringify(states[0]);
  assert(states.every((state) => JSON.stringify(state) === canonical),
    `${description}: four projections must match`);
  return states[0];
}

async function answerQuestion(runtime, matchId, questionIndex, metrics) {
  const privateState = await readPrivate(runtime, matchId);
  const question = privateState.currentQuestion;
  const publicState = await waitForPhase(
    runtime,
    PHASE.QUESTION_OPEN,
    questionIndex,
    `QUESTION_OPEN ${questionIndex}`
  );
  assert(!Object.hasOwn(publicState.currentQuestion, "correctAnswerId"),
    `question ${questionIndex}: correct answer must stay private while open`);

  const correct = question.correctAnswerId;
  const wrong = question.choices.find((choice) => choice.answerId !== correct).answerId;
  const strategy = questionStrategy(questionIndex);
  const accepted = [];

  if (strategy === "SECURITY_AND_IDEMPOTENCY") {
    const player = runtime.players[0];
    const staleQuestion = await submitAnswer(
      runtime,
      matchId,
      player,
      { ...question, questionId: "stale-question" },
      publicState.stateVersion,
      correct,
      `stale-question-${randomUUID()}`
    );
    assert(staleQuestion.ack.rejectionCode === "QUESTION_MISMATCH",
      "stale question must be rejected");

    const staleState = await submitAnswer(
      runtime,
      matchId,
      player,
      question,
      Math.max(0, publicState.stateVersion - 1),
      correct,
      `stale-state-${randomUUID()}`
    );
    assert(staleState.ack.rejectionCode === "STALE_STATE_VERSION",
      "stale stateVersion must be rejected");

    const wrongSessionEvent = envelope(
      player,
      matchId,
      "submitAnswer",
      `wrong-session-${randomUUID()}`,
      {
        sessionId: "wrong-session",
        questionId: question.questionId,
        stateVersion: publicState.stateVersion,
        payload: { answerId: correct },
      }
    );
    const wrongSession = await callIntent(runtime, player, wrongSessionEvent);
    assert(wrongSession.ack.rejectionCode === "STALE_SESSION_EPOCH",
      "wrong session must be rejected");

    const stableEventId = `stable-retry-${randomUUID()}`;
    const stableEvent = envelope(player, matchId, "submitAnswer", stableEventId, {
      questionId: question.questionId,
      stateVersion: publicState.stateVersion,
      payload: { answerId: correct },
    });
    const first = await callIntent(runtime, player, stableEvent);
    assert(first.ack.status === "ACCEPTED", "first stable event must be accepted");
    accepted.push(first);
    const retry = await callIntent(runtime, player, stableEvent);
    assert(retry.ack.status === "DUPLICATE" && retry.ack.originalStatus === "ACCEPTED",
      "same event retry must preserve accepted result");
    const second = await submitAnswer(
      runtime,
      matchId,
      player,
      question,
      publicState.stateVersion,
      correct,
      `second-answer-${randomUUID()}`
    );
    assert(second.ack.rejectionCode === "ALREADY_ANSWERED",
      "different second answer must be rejected");

    for (const other of runtime.players.slice(1)) {
      accepted.push(await submitAnswer(
        runtime,
        matchId,
        other,
        question,
        publicState.stateVersion,
        correct,
        `answer-q${questionIndex}-${randomUUID()}`
      ));
    }
  } else if (strategy === "DEADLINE_WITH_UNANSWERED") {
    const answerIds = [correct, wrong, correct];
    for (const [index, player] of runtime.players.slice(0, 3).entries()) {
      accepted.push(await submitAnswer(
        runtime,
        matchId,
        player,
        question,
        publicState.stateVersion,
        answerIds[index],
        `answer-q${questionIndex}-${randomUUID()}`
      ));
    }
    await waitUntilEpoch(question.deadlineEpochMs, 500);
    await callReconcile(runtime, runtime.players[0], matchId, `deadline-${questionIndex}`);
  } else {
    const answerIds = strategy === "WRONG_THEN_CORRECT"
      ? [wrong, correct, correct, correct]
      : [correct, correct, correct, correct];
    for (const [index, player] of runtime.players.entries()) {
      accepted.push(await submitAnswer(
        runtime,
        matchId,
        player,
        question,
        publicState.stateVersion,
        answerIds[index],
        `answer-q${questionIndex}-${randomUUID()}`
      ));
    }
  }

  for (const outcome of accepted) {
    assert(outcome.ack.status === "ACCEPTED", `question ${questionIndex}: answer rejected`);
    assert(Number.isFinite(outcome.metric.t1ToT2Ms), "T1 to T2 timing is required");
    assert(Number.isFinite(outcome.metric.t0ToT3Ms), "T0 to T3 timing is required");
    assert(Number.isFinite(outcome.metric.t0ToT4Ms), "T0 to T4 timing is required");
    metrics.push(outcome.metric);
  }

  const resultState = await waitForPhase(
    runtime,
    PHASE.QUESTION_RESULT,
    questionIndex,
    `QUESTION_RESULT ${questionIndex}`
  );
  const result = resultState.questionResult;
  assert(result.correctAnswerId === correct, "correct answer must be published after result");

  if (strategy === "ALL_CORRECT_ORDERED" || strategy === "SECURITY_AND_IDEMPOTENCY") {
    assertScoreDeltas(result, new Map(runtime.players.map((player, index) => [
      player.uid,
      [20, 10, 5, 1][index],
    ])), `question ${questionIndex}`);
  } else if (strategy === "WRONG_THEN_CORRECT") {
    assertScoreDeltas(result, new Map([
      [runtime.players[0].uid, -10],
      [runtime.players[1].uid, 20],
      [runtime.players[2].uid, 10],
      [runtime.players[3].uid, 5],
    ]), "wrong answer ranking");
  } else {
    assert(result.closeReason === "DEADLINE", "deadline question must close by deadline");
    assertScoreDeltas(result, new Map([
      [runtime.players[0].uid, 20],
      [runtime.players[1].uid, -10],
      [runtime.players[2].uid, 10],
      [runtime.players[3].uid, 0],
    ]), "deadline scoring");
    assert(result.unansweredUIDs.includes(runtime.players[3].uid),
      "unanswered player must be reported");
  }

  if (strategy === "SECURITY_AND_IDEMPOTENCY") {
    const afterResult = await submitAnswer(
      runtime,
      matchId,
      runtime.players[1],
      question,
      resultState.stateVersion,
      correct,
      `after-result-${randomUUID()}`
    );
    assert(afterResult.ack.rejectionCode === "INVALID_MATCH_STATE",
      "answer after result must be rejected");
  }
  return result;
}

async function advance(runtime, matchId, questionIndex) {
  const resultState = runtime.players[0].tracker.latest;
  await waitUntilEpoch(resultState.resultEndsAtEpochMs, 250);
  await callReconcile(runtime, runtime.players[0], matchId, `result-${questionIndex}`);
  if (questionIndex + 1 >= QUESTION_COUNT) {
    return waitForPhase(runtime, PHASE.MATCH_FINISHED, questionIndex, "MATCH_FINISHED");
  }
  await waitForPhase(runtime, PHASE.NEXT_QUESTION, questionIndex, `NEXT_QUESTION ${questionIndex}`);
  await callReconcile(runtime, runtime.players[0], matchId, `next-${questionIndex}`);
  return waitForPhase(
    runtime,
    PHASE.QUESTION_OPEN,
    questionIndex + 1,
    `QUESTION_OPEN ${questionIndex + 1}`
  );
}

async function executeCloudE2E(config) {
  const matchId = makeMatchId();
  let runtime = null;
  let cleanupRequired = false;
  let cleanupConfirmed = false;
  const answerMetrics = [];
  const cumulative = new Map(config.testUIDs.map((uid) => [uid, 0]));
  let firstInvocationMetric = null;
  let report = null;

  try {
    runtime = await createRuntime(config, matchId);
    const match = buildTestMatch({
      matchId,
      players: runtime.players.map((player, index) => ({
        uid: player.uid,
        displayName: `Cloud Test ${index + 1}`,
        sessionId: player.sessionId,
        sessionEpoch: player.sessionEpoch,
        assignmentTicket: player.assignmentTicket,
      })),
      createdAtEpochMs: Date.now(),
      countdownDurationMs: 500,
      questionDurationMs: 10_000,
      resultDurationMs: 250,
    });
    cleanupRequired = true;
    await runtime.adminRTDB.ref(`${ROOT_PATH}/matches/${matchId}`).set(match);
    for (const player of runtime.players) {
      player.tracker = createTracker(
        player.database,
        matchId,
        runtime.sdk.clientDatabase
      );
    }

    const created = await callReconcile(runtime, runtime.players[0], matchId, "created");
    assert(created.ack.status === "ACCEPTED", "CREATED reconciliation must succeed");
    firstInvocationMetric = created.metric;
    await waitForPhase(runtime, PHASE.WAITING_PLAYERS, -1, "WAITING_PLAYERS");

    await assertPrivateDenied(runtime.players[0], matchId, runtime.sdk.clientDatabase);

    for (const [index, player] of runtime.players.entries()) {
      const join = await callIntent(runtime, player, envelope(
        player,
        matchId,
        "joinMatch",
        `join-${index}-${randomUUID()}`,
        { payload: { assignmentTicket: player.assignmentTicket } }
      ));
      assert(join.ack.status === "ACCEPTED", `player ${index + 1} join failed`);
    }
    for (const [index, player] of runtime.players.entries()) {
      const ready = await callIntent(runtime, player, envelope(
        player,
        matchId,
        "ready",
        `ready-${index}-${randomUUID()}`
      ));
      assert(ready.ack.status === "ACCEPTED", `player ${index + 1} ready failed`);
    }

    const countdown = await waitForPhase(runtime, PHASE.COUNTDOWN, -1, "COUNTDOWN");
    await waitUntilEpoch(countdown.countdownEndsAtEpochMs, 250);
    await callReconcile(runtime, runtime.players[0], matchId, "countdown");
    await waitForPhase(runtime, PHASE.QUESTION_OPEN, 0, "first QUESTION_OPEN");

    for (let questionIndex = 0; questionIndex < QUESTION_COUNT; questionIndex += 1) {
      const result = await answerQuestion(runtime, matchId, questionIndex, answerMetrics);
      for (const [uid, score] of Object.entries(result.scoreDeltas)) {
        cumulative.set(uid, (cumulative.get(uid) || 0) + score);
      }
      await advance(runtime, matchId, questionIndex);
    }

    const finalState = await waitForPhase(
      runtime,
      PHASE.MATCH_FINISHED,
      QUESTION_COUNT - 1,
      "final MATCH_FINISHED"
    );
    for (const [uid, expectedScore] of cumulative.entries()) {
      assert(finalState.finalResult.finalScores[uid] === expectedScore,
        "final score must equal accumulated question results");
    }

    for (const player of runtime.players) {
      const phases = new Set(player.tracker.observations.map(
        (observation) => observation.state.phase
      ));
      for (const phase of [
        PHASE.QUESTION_OPEN,
        PHASE.QUESTION_RESULT,
        PHASE.NEXT_QUESTION,
        PHASE.MATCH_FINISHED,
      ]) {
        assert(phases.has(phase), `client projection must observe ${phase}`);
      }
    }

    report = {
      status: "passed",
      projectId: config.projectId,
      region: REGION,
      matchId,
      players: runtime.players.length,
      questions: QUESTION_COUNT,
      firstInvocation: firstInvocationMetric,
      answerLatency: latencySummary(answerMetrics),
      answerInvocations: {
        cold: answerMetrics.filter((metric) => metric.coldInstanceInvocation).length,
        warm: answerMetrics.filter((metric) => metric.coldInstanceInvocation === false).length,
        distinctInstances: new Set(answerMetrics.map((metric) => metric.instanceId)).size,
      },
      assertions: {
        privateReadDenied: true,
        independentAnswers: true,
        scoring: true,
        deadlineAndAllAnswered: true,
        duplicateAndRetry: true,
        staleAndSessionRejection: true,
        fourClientProjection: true,
        finalScores: true,
      },
    };
  } finally {
    if (runtime && cleanupRequired) {
      await runtime.adminRTDB.ref(`${ROOT_PATH}/matches/${matchId}`).remove();
      await runtime.adminRTDB.ref(`${ROOT_PATH}/clocks/${matchId}`).remove();
      const [matchSnapshot, clockSnapshot] = await Promise.all([
        runtime.adminRTDB.ref(`${ROOT_PATH}/matches/${matchId}`).get(),
        runtime.adminRTDB.ref(`${ROOT_PATH}/clocks/${matchId}`).get(),
      ]);
      cleanupConfirmed = !matchSnapshot.exists() && !clockSnapshot.exists();
    }
    if (runtime) await closeRuntime(runtime);
    if (cleanupRequired && !cleanupConfirmed) {
      throw new Error(`Cleanup could not be confirmed for test match ${matchId}`);
    }
  }
  report.cleanup = {
    confirmed: cleanupConfirmed,
    paths: [
      `${ROOT_PATH}/matches/${matchId}`,
      `${ROOT_PATH}/clocks/${matchId}`,
    ],
  };
  return report;
}

function safeErrorMessage(error) {
  return String(error?.message || error || "Unknown error")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[REDACTED_TOKEN]")
    .replace(/AIza[0-9A-Za-z_-]{35}/g, "[REDACTED_API_KEY]");
}

async function main() {
  if (process.argv.includes("--review")) {
    process.stdout.write(`${JSON.stringify(reviewPlan(), null, 2)}\n`);
    return;
  }
  if (!process.argv.includes("--execute")) {
    throw new Error("Refusing to run. Use --review, or --execute after explicit Production approval");
  }
  const result = await executeCloudE2E(executionConfiguration());
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${safeErrorMessage(error)}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  EXECUTION_CONFIRMATION,
  DATABASE_HOST,
  PROJECT_ID,
  executionConfiguration,
  latencySummary,
  makeMatchId,
  parseTestUIDs,
  questionStrategy,
  reviewPlan,
};
