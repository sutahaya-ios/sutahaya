const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, before, beforeEach, describe, it } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { deleteApp, initializeApp } = require("firebase/app");
const { connectAuthEmulator, getAuth, signInAnonymously } = require("firebase/auth");
const {
  connectDatabaseEmulator,
  get,
  getDatabase,
  goOffline,
  onValue,
  ref,
  set,
} = require("firebase/database");
const {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} = require("firebase/functions");

const { PHASE, PROTOCOL_VERSION } = require("../functions/competitive/constants");
const { buildTestMatch } = require("../functions/competitive/testMatchFactory");

const projectId = "demo-hayaosiapp";
const rootDir = path.resolve(__dirname, "..");
const region = "asia-southeast1";
const publicPhases = new Set([
  PHASE.QUESTION_OPEN,
  PHASE.QUESTION_RESULT,
  PHASE.NEXT_QUESTION,
  PHASE.MATCH_FINISHED,
]);

let testEnv;
let clientApps = [];

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    database: {
      rules: fs.readFileSync(path.join(rootDir, "database.rules.json"), "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearDatabase();
  await adminRequest("", "DELETE");
});

after(async () => {
  await Promise.all(clientApps.map(async (app) => {
    goOffline(getDatabase(app));
    await deleteApp(app);
  }));
  await testEnv.cleanup();
});

async function adminRequest(databasePath, method = "GET", body = undefined) {
  const normalizedPath = databasePath ? `/${databasePath}` : "/";
  const response = await fetch(
    `http://127.0.0.1:9100${normalizedPath}.json?ns=${projectId}`,
    {
      method,
      headers: {
        Authorization: "Bearer owner",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    }
  );
  if (!response.ok) {
    throw new Error(`Admin RTDB request failed: ${method} ${databasePath} ${response.status}`);
  }
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function createClient({ authenticated = true } = {}) {
  const app = initializeApp({
    apiKey: "demo-key",
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
    databaseURL: `https://${projectId}.firebaseio.com`,
  }, `competitive-test-${randomUUID()}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  let uid = null;
  if (authenticated) {
    uid = (await signInAnonymously(auth)).user.uid;
  }
  const functions = getFunctions(app, region);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const database = getDatabase(app);
  connectDatabaseEmulator(database, "127.0.0.1", 9100);
  return { app, auth, uid, functions, database };
}

async function createFourClients() {
  const clients = await Promise.all([0, 1, 2, 3].map(() => createClient()));
  return clients.map((client, index) => ({
    ...client,
    displayName: `Player ${index + 1}`,
    sessionId: `session-${index + 1}-${randomUUID()}`,
    sessionEpoch: 1,
    assignmentTicket: `ticket-${index + 1}-${randomUUID()}`,
  }));
}

function envelope(client, matchId, type, suffix, overrides = {}) {
  return {
    intentId: `event-${suffix}-${randomUUID()}`,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-a2-emulator",
    sessionId: client.sessionId,
    sessionEpoch: client.sessionEpoch,
    matchId,
    lastSeenServerSequence: 0,
    payload: {},
    ...overrides,
  };
}

async function callIntent(client, event) {
  return (await httpsCallable(client.functions, "competitiveIntent")(event)).data;
}

async function callReconcile(client, matchId, suffix) {
  const event = envelope(client, matchId, "reconcile", suffix);
  return (await httpsCallable(client.functions, "competitiveReconcileMatch")(event)).data;
}

async function seedMatch(clients, options = {}) {
  const matchId = `match-${randomUUID()}`;
  const match = buildTestMatch({
    matchId,
    players: clients.map((client) => ({
      uid: client.uid,
      displayName: client.displayName,
      sessionId: client.sessionId,
      sessionEpoch: client.sessionEpoch,
      assignmentTicket: client.assignmentTicket,
    })),
    createdAtEpochMs: Date.now(),
    countdownDurationMs: options.countdownDurationMs ?? 5,
    questionDurationMs: options.questionDurationMs ?? 5_000,
    resultDurationMs: options.resultDurationMs ?? 5,
  });
  await adminRequest(`competitiveV2/matches/${matchId}`, "PUT", match);
  const saved = await adminRequest(`competitiveV2/matches/${matchId}`);
  assert.ok(saved?.private, "seeded private match must be visible in the Functions namespace");
  return { matchId, match };
}

async function readPrivate(matchId) {
  return adminRequest(`competitiveV2/matches/${matchId}/private`);
}

async function readPublic(client, matchId) {
  return (await get(ref(
    client.database,
    `competitiveV2/matches/${matchId}/public`
  ))).val();
}

async function waitFor(predicate, description, timeoutMs = 5_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(10);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function waitForPublic(client, matchId, predicate, description) {
  await waitFor(async () => predicate(await readPublic(client, matchId)), description);
  return readPublic(client, matchId);
}

function observePublic(client, matchId) {
  const observations = [];
  let latest = null;
  const unsubscribe = onValue(
    ref(client.database, `competitiveV2/matches/${matchId}/public`),
    (snapshot) => {
      latest = snapshot.val();
      if (latest) observations.push(latest);
    }
  );
  return {
    get latest() { return latest; },
    observations,
    unsubscribe,
  };
}

async function waitForTrackers(trackers, predicate, description) {
  await waitFor(
    () => trackers.every((tracker) => tracker.latest && predicate(tracker.latest)),
    description
  );
}

async function joinReadyAndOpen(clients, matchId) {
  assert.equal((await callReconcile(clients[0], matchId, "created")).status, "ACCEPTED");
  for (const [index, client] of clients.entries()) {
    const join = envelope(client, matchId, "joinMatch", `join-${index}`, {
      payload: { assignmentTicket: client.assignmentTicket },
    });
    assert.equal((await callIntent(client, join)).status, "ACCEPTED");
  }
  for (const [index, client] of clients.entries()) {
    assert.equal((await callIntent(
      client,
      envelope(client, matchId, "ready", `ready-${index}`)
    )).status, "ACCEPTED");
  }
  await delay(10);
  assert.equal((await callReconcile(clients[0], matchId, "countdown")).status, "ACCEPTED");
  return waitForPublic(
    clients[0],
    matchId,
    (value) => value?.phase === PHASE.QUESTION_OPEN,
    "QUESTION_OPEN"
  );
}

async function answerCurrentQuestion(clients, matchId, selection = "correct") {
  const state = await readPrivate(matchId);
  const question = state.currentQuestion;
  const answerIds = clients.map((_, index) => {
    if (selection === "mixed" && index === 3) {
      return question.choices.find(
        (choice) => choice.answerId !== question.correctAnswerId
      ).answerId;
    }
    return question.correctAnswerId;
  });
  const events = clients.map((client, index) => envelope(
    client,
    matchId,
    "submitAnswer",
    `q${state.currentQuestionIndex}-p${index}`,
    {
      questionId: question.questionId,
      stateVersion: state.stateVersion,
      payload: { answerId: answerIds[index] },
    }
  ));
  const acks = await Promise.all(events.map((event, index) => callIntent(clients[index], event)));
  return { acks, events, answerIds };
}

async function advanceFromResult(clients, matchId, questionIndex) {
  await delay(10);
  await callReconcile(clients[0], matchId, `result-${questionIndex}`);
  let projection = await readPublic(clients[0], matchId);
  if (projection.phase === PHASE.NEXT_QUESTION) {
    await callReconcile(clients[0], matchId, `next-${questionIndex}`);
    projection = await waitForPublic(
      clients[0],
      matchId,
      (value) => value?.phase === PHASE.QUESTION_OPEN,
      `QUESTION_OPEN ${questionIndex + 1}`
    );
  }
  return projection;
}

describe("Competitive Core emulator", { concurrency: false }, () => {
  it("enforces the public/private RTDB boundary", async () => {
    const matchId = "rules-boundary";
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await set(ref(context.database(), `competitiveV2/matches/${matchId}`), {
        private: {
          participants: {
            member: { uid: "member" },
          },
          correctAnswer: "secret",
        },
        public: { phase: PHASE.WAITING_PLAYERS },
      });
    });
    const member = testEnv.authenticatedContext("member").database();
    const outsider = testEnv.authenticatedContext("outsider").database();

    await assertSucceeds(get(ref(member, `competitiveV2/matches/${matchId}/public`)));
    await assertFails(get(ref(member, `competitiveV2/matches/${matchId}/private`)));
    await assertFails(get(ref(outsider, `competitiveV2/matches/${matchId}/public`)));
    await assertFails(set(
      ref(member, `competitiveV2/matches/${matchId}/public/phase`),
      PHASE.MATCH_FINISHED
    ));
    await assertFails(set(
      ref(member, `competitiveV2/matches/${matchId}/private/answerInbox/q/member`),
      { answerId: "spoof" }
    ));
  });

  it("completes one independent-answer question and rejects Security Gate A attacks", async () => {
    const clients = await createFourClients();
    const outsider = await createClient();
    const unauthenticated = await createClient({ authenticated: false });
    const { matchId } = await seedMatch(clients);
    await joinReadyAndOpen(clients, matchId);
    const before = await readPrivate(matchId);
    const question = before.currentQuestion;
    const baseEvent = envelope(clients[0], matchId, "submitAnswer", "security-base", {
      questionId: question.questionId,
      stateVersion: before.stateVersion,
      payload: { answerId: question.correctAnswerId },
    });

    await assert.rejects(
      httpsCallable(unauthenticated.functions, "competitiveIntent")(baseEvent),
      (error) => error.code === "functions/unauthenticated"
    );

    const outsiderEvent = {
      ...baseEvent,
      intentId: `event-outsider-${randomUUID()}`,
      sessionId: clients[0].sessionId,
    };
    const beforeUnauthorized = await readPrivate(matchId);
    assert.equal((await callIntent(outsider, outsiderEvent)).rejectionCode, "NOT_MATCH_MEMBER");
    const outsiderReconcile = envelope(clients[0], matchId, "reconcile", "outsider-reconcile", {
      sessionId: clients[0].sessionId,
    });
    assert.equal(
      (await httpsCallable(
        outsider.functions,
        "competitiveReconcileMatch"
      )(outsiderReconcile)).data.rejectionCode,
      "NOT_MATCH_MEMBER"
    );
    const afterOutsider = await readPrivate(matchId);
    assert.equal(afterOutsider.serverSequence, beforeUnauthorized.serverSequence);
    assert.deepEqual(afterOutsider.audit || {}, beforeUnauthorized.audit || {});
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-other-uid-${randomUUID()}`,
      playerId: clients[1].uid,
    })).rejectionCode, "INVALID_PAYLOAD");
    const beforeWrongSession = await readPrivate(matchId);
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-wrong-session-${randomUUID()}`,
      sessionId: "wrong-session",
    })).rejectionCode, "STALE_SESSION_EPOCH");
    const afterWrongSession = await readPrivate(matchId);
    assert.equal(afterWrongSession.serverSequence, beforeWrongSession.serverSequence);
    assert.deepEqual(afterWrongSession.audit || {}, beforeWrongSession.audit || {});
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-stale-question-${randomUUID()}`,
      questionId: "stale-question",
    })).rejectionCode, "QUESTION_MISMATCH");
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-stale-state-${randomUUID()}`,
      stateVersion: question.openedStateVersion - 1,
    })).rejectionCode, "STALE_STATE_VERSION");
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-score-spoof-${randomUUID()}`,
      score: 999,
    })).rejectionCode, "INVALID_PAYLOAD");
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-correct-spoof-${randomUUID()}`,
      payload: { answerId: question.correctAnswerId, correct: true },
    })).rejectionCode, "INVALID_PAYLOAD");
    assert.equal((await callIntent(clients[0], null)).rejectionCode, "INVALID_PAYLOAD");
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-oversized-${randomUUID()}`,
      padding: "x".repeat(5_000),
    })).rejectionCode, "PAYLOAD_TOO_LARGE");
    assert.equal((await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-unknown-${randomUUID()}`,
      matchId: "unknown-match",
    })).rejectionCode, "UNKNOWN_MATCH");

    const accepted = await callIntent(clients[0], baseEvent);
    const retry = await callIntent(clients[0], baseEvent);
    assert.equal(accepted.status, "ACCEPTED");
    assert.ok(Number.isFinite(accepted.timing.t1EpochMs));
    assert.ok(Number.isFinite(accepted.timing.t2EpochMs));
    assert.ok(Number.isFinite(accepted.timing.t1ToT2Ms));
    assert.ok(Number.isFinite(accepted.timing.authorityTimestampEpochMs));
    assert.equal(typeof accepted.runtime.instanceId, "string");
    assert.equal(typeof accepted.runtime.coldInstanceInvocation, "boolean");
    assert.equal(retry.status, "DUPLICATE");
    assert.equal(retry.originalStatus, "ACCEPTED");

    const secondAnswer = await callIntent(clients[0], {
      ...baseEvent,
      intentId: `event-second-answer-${randomUUID()}`,
    });
    assert.equal(secondAnswer.rejectionCode, "ALREADY_ANSWERED");

    await assertFails(set(
      ref(clients[1].database, `competitiveV2/matches/${matchId}/private/answerInbox/${question.questionId}/${clients[0].uid}`),
      { answerId: "overwrite" }
    ));
    await assertFails(get(ref(
      clients[0].database,
      `competitiveV2/matches/${matchId}/private/currentQuestion`
    )));

    const remaining = clients.slice(1);
    const current = await readPrivate(matchId);
    const remainingAcks = await Promise.all(remaining.map((client, index) => callIntent(
      client,
      envelope(client, matchId, "submitAnswer", `security-finish-${index}`, {
        questionId: current.currentQuestion.questionId,
        stateVersion: current.stateVersion,
        payload: { answerId: current.currentQuestion.correctAnswerId },
      })
    )));
    assert.ok(remainingAcks.every((ack) => ack.status === "ACCEPTED"));
    const result = await readPublic(clients[0], matchId);
    assert.equal(result.phase, PHASE.QUESTION_RESULT);
    assert.equal(result.questionResult.answerOrder.length, 4);

    const afterResult = await callIntent(clients[1], {
      ...baseEvent,
      intentId: `event-after-result-${randomUUID()}`,
      sessionId: clients[1].sessionId,
      questionId: result.currentQuestion.questionId,
      stateVersion: result.stateVersion,
    });
    assert.equal(afterResult.rejectionCode, "INVALID_MATCH_STATE");
  });

  it("converges a deadline answer/close race without changing the finalized result", async () => {
    const clients = await createFourClients();
    const { matchId } = await seedMatch(clients, { questionDurationMs: 30 });
    await joinReadyAndOpen(clients, matchId);
    const opened = await readPrivate(matchId);
    await delay(40);
    const lateEvent = envelope(clients[0], matchId, "submitAnswer", "deadline-late", {
      questionId: opened.currentQuestion.questionId,
      stateVersion: opened.stateVersion,
      payload: { answerId: opened.currentQuestion.correctAnswerId },
    });

    const [answerAck] = await Promise.all([
      callIntent(clients[0], lateEvent),
      callReconcile(clients[1], matchId, "deadline-close"),
    ]);
    assert.ok(["DEADLINE_EXCEEDED", "INVALID_MATCH_STATE"].includes(answerAck.rejectionCode));
    const finalized = await readPrivate(matchId);
    assert.equal(finalized.phase, PHASE.QUESTION_RESULT);
    assert.deepEqual(finalized.currentQuestion.result.answerOrder || [], []);
    assert.deepEqual(finalized.currentQuestion.result.cumulativeScores, Object.fromEntries(
      clients.map((client) => [client.uid, 0])
    ));

    await callReconcile(clients[0], matchId, "deadline-close-retry");
    const afterRetry = await readPrivate(matchId);
    assert.deepEqual(afterRetry.currentQuestion.result, finalized.currentQuestion.result);
  });

  it("keeps four realtime projections synchronized through all 20 questions", async () => {
    const clients = await createFourClients();
    const { matchId } = await seedMatch(clients);
    await callReconcile(clients[0], matchId, "created-before-listeners");
    const trackers = clients.map((client) => observePublic(client, matchId));
    await waitForTrackers(trackers, (value) => value.phase === PHASE.WAITING_PLAYERS, "listeners ready");

    for (const [index, client] of clients.entries()) {
      const join = envelope(client, matchId, "joinMatch", `full-join-${index}`, {
        payload: { assignmentTicket: client.assignmentTicket },
      });
      assert.equal((await callIntent(client, join)).status, "ACCEPTED");
    }
    for (const [index, client] of clients.entries()) {
      assert.equal((await callIntent(
        client,
        envelope(client, matchId, "ready", `full-ready-${index}`)
      )).status, "ACCEPTED");
    }
    await delay(10);
    await callReconcile(clients[0], matchId, "full-countdown");
    await waitForTrackers(trackers, (value) => value.phase === PHASE.QUESTION_OPEN, "first question");

    const questionResults = [];
    for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
      const { acks } = await answerCurrentQuestion(clients, matchId, "correct");
      assert.ok(acks.every((ack) => ack.status === "ACCEPTED"));
      await waitForTrackers(
        trackers,
        (value) => value.phase === PHASE.QUESTION_RESULT
          && value.currentQuestionIndex === questionIndex
          && Object.values(value.participants).every((participant) => participant.answered),
        `QUESTION_RESULT ${questionIndex}`
      );
      const projection = trackers[0].latest;
      questionResults.push(projection.questionResult);
      assert.equal(projection.questionResult.answerOrder.length, 4);
      assert.equal(Object.values(projection.questionResult.scoreDeltas).reduce(
        (sum, value) => sum + value,
        0
      ), 36);

      const next = await advanceFromResult(clients, matchId, questionIndex);
      if (questionIndex < 19) {
        assert.equal(next.phase, PHASE.QUESTION_OPEN);
        await waitForTrackers(
          trackers,
          (value) => value.phase === PHASE.QUESTION_OPEN
            && value.currentQuestionIndex === questionIndex + 1
            && Object.values(value.participants).every((participant) => !participant.answered),
          `clean QUESTION_OPEN ${questionIndex + 1}`
        );
      }
    }

    await waitForTrackers(trackers, (value) => value.phase === PHASE.MATCH_FINISHED, "MATCH_FINISHED");
    const finalProjection = trackers[0].latest;
    assert.equal(questionResults.length, 20);
    assert.equal(Object.values(finalProjection.finalResult.finalScores).reduce(
      (sum, value) => sum + value,
      0
    ), 720);
    assert.equal(finalProjection.currentQuestionIndex, 19);

    for (const tracker of trackers) {
      const versions = tracker.observations.map((value) => value.stateVersion);
      assert.ok(versions.every((value, index) => index === 0 || value >= versions[index - 1]));
      const orderedPhases = [];
      for (const value of tracker.observations) {
        if (!publicPhases.has(value.phase)) continue;
        const key = `${value.phase}:${value.currentQuestionIndex}`;
        if (orderedPhases.at(-1) !== key) orderedPhases.push(key);
      }
      assert.deepEqual(orderedPhases, trackers[0].observations.reduce((phases, value) => {
        if (!publicPhases.has(value.phase)) return phases;
        const key = `${value.phase}:${value.currentQuestionIndex}`;
        if (phases.at(-1) !== key) phases.push(key);
        return phases;
      }, []));
      assert.deepEqual(tracker.latest, finalProjection);
      tracker.unsubscribe();
    }

    const privateState = await readPrivate(matchId);
    assert.equal(privateState.currentQuestionIndex, 19);
    assert.equal(privateState.phase, PHASE.MATCH_FINISHED);
    assert.equal(privateState.questionInstances.length, 20);
    assert.equal(Object.keys(privateState.currentQuestion.answers).length, 4);
  });
});
