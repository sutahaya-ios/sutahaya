const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, before, beforeEach, describe, it } = require("node:test");
const {
  assertFails,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { deleteApp, initializeApp } = require("firebase/app");
const { connectAuthEmulator, getAuth, signInAnonymously } = require("firebase/auth");
const {
  connectDatabaseEmulator,
  get,
  getDatabase,
  goOffline,
  ref,
  set,
} = require("firebase/database");
const {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} = require("firebase/functions");

const { PHASE, PROTOCOL_VERSION } = require("../functions/competitive/constants");

const projectId = "demo-hayaosiapp";
const rootDir = path.resolve(__dirname, "..");
const region = "asia-southeast1";
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
  const normalized = databasePath ? `/${databasePath}` : "/";
  const response = await fetch(
    `http://127.0.0.1:9100${normalized}.json?ns=${projectId}`,
    {
      method,
      headers: {
        Authorization: "Bearer owner",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    }
  );
  if (!response.ok) throw new Error(`Admin RTDB request failed: ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitFor(predicate, description, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await delay(20);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function createClient() {
  const app = initializeApp({
    apiKey: "demo-key",
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
    databaseURL: `https://${projectId}.firebaseio.com`,
  }, `phase-d1-${randomUUID()}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const uid = (await signInAnonymously(auth)).user.uid;
  const functions = getFunctions(app, region);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const database = getDatabase(app);
  connectDatabaseEmulator(database, "127.0.0.1", 9100);
  return { app, uid, functions, database };
}

async function call(client, functionName, payload) {
  return (await httpsCallable(client.functions, functionName)(payload)).data;
}

async function matchmaking(client, payload) {
  return call(client, "competitiveMatchmaking", payload);
}

async function projection(client) {
  return (await get(ref(
    client.database,
    `competitiveV2/matchmaking/public/${client.uid}`
  ))).val();
}

function envelope(session, type, suffix, overrides = {}) {
  return {
    intentId: `${type}-${suffix}-${randomUUID()}`,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-d1-emulator",
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    matchId: session.matchId,
    lastSeenServerSequence: 0,
    payload: {},
    ...overrides,
  };
}

async function reconcile(client, session, suffix) {
  return call(client, "competitiveReconcileMatch", envelope(
    session,
    "reconcile",
    suffix
  ));
}

async function createMixedMatch() {
  const clients = await Promise.all([createClient(), createClient()]);
  const joins = await Promise.all(clients.map((client) => matchmaking(client, {
    intentId: `join-${randomUUID()}`,
    type: "joinQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-d1-emulator",
    payload: {},
  })));
  const oldQueuedAt = Date.now() - 5_100;
  await Promise.all(clients.map((client) => adminRequest(
    `competitiveV2/matchmaking/private/queue/${client.uid}/queuedAtEpochMs`,
    "PUT",
    oldQueuedAt
  )));
  await matchmaking(clients[0], {
    intentId: `check-${randomUUID()}`,
    type: "checkQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-d1-emulator",
    sessionId: joins[0].sessionId,
    sessionEpoch: joins[0].sessionEpoch,
    payload: {},
  });
  const sessions = await Promise.all(clients.map((client) => waitFor(async () => {
    const value = await projection(client);
    return value?.state === "WAITING_PLAYERS" ? value : null;
  }, "mixed match assignment")));
  assert.equal(new Set(sessions.map((value) => value.matchId)).size, 1);
  return { clients, sessions, matchId: sessions[0].matchId };
}

async function joinReadyOpen({ clients, sessions, matchId }) {
  await adminRequest(`competitiveV2/matches/${matchId}/private/config`, "PATCH", {
    countdownDurationMs: 1,
    questionDurationMs: 1_000,
    resultDurationMs: 1,
    npcSkillInput: {
      ...(await adminRequest(`competitiveV2/matches/${matchId}/private/config/npcSkillInput`)),
      reactionBaseMs: 5,
    },
  });
  for (const [index, client] of clients.entries()) {
    const session = sessions[index];
    assert.equal((await call(client, "competitiveIntent", envelope(
      session,
      "joinMatch",
      `join-${index}`,
      { payload: { assignmentTicket: session.assignmentTicket } }
    ))).status, "ACCEPTED");
  }
  for (const [index, client] of clients.entries()) {
    assert.equal((await call(client, "competitiveIntent", envelope(
      sessions[index],
      "ready",
      `ready-${index}`
    ))).status, "ACCEPTED");
  }
  await delay(3);
  await reconcile(clients[0], sessions[0], "open-first");
}

async function playTwentyQuestions(context) {
  const { clients, sessions, matchId } = context;
  for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
    let state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    assert.equal(state.phase, PHASE.QUESTION_OPEN);
    const wrong = state.currentQuestion.choices.find(
      (choice) => choice.answerId !== state.currentQuestion.correctAnswerId
    ).answerId;
    const answers = [state.currentQuestion.correctAnswerId, wrong];
    const acknowledgements = await Promise.all(clients.map((client, index) => call(
      client,
      "competitiveIntent",
      envelope(sessions[index], "submitAnswer", `${questionIndex}-${index}`, {
        questionId: state.currentQuestion.questionId,
        stateVersion: state.stateVersion,
        payload: { answerId: answers[index] },
      })
    )));
    assert.deepEqual(
      acknowledgements.map((acknowledgement) => acknowledgement.status),
      ["ACCEPTED", "ACCEPTED"]
    );
    await delay(15);
    state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    if (state.phase === PHASE.QUESTION_OPEN) {
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/currentQuestion/deadlineEpochMs`,
        "PUT",
        Date.now() - 1
      );
      await reconcile(clients[0], sessions[0], `close-${questionIndex}`);
    }
    state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    assert.equal(state.phase, PHASE.QUESTION_RESULT);
    await adminRequest(
      `competitiveV2/matches/${matchId}/private/resultEndsAtEpochMs`,
      "PUT",
      Date.now() - 1
    );
    await reconcile(clients[0], sessions[0], `advance-${questionIndex}`);
    if (questionIndex < 19) {
      await reconcile(clients[0], sessions[0], `next-${questionIndex}`);
    }
  }
}

describe("Competitive Phase D-1 Emulator", () => {
  it("settles a 20-question Human/NPC match with rating, stats and server-only security", async () => {
    const context = await createMixedMatch();
    const before = await adminRequest("competitiveV2/matchmaking/private/profiles");
    const matchBefore = await adminRequest(`competitiveV2/matches/${context.matchId}/private`);
    const participants = Object.values(matchBefore.participants);
    assert.equal(participants.filter((value) => value.kind === "HUMAN").length, 2);
    assert.equal(participants.filter((value) => value.kind === "NPC").length, 2);
    assert.equal(matchBefore.config.npcSkillInput.sourceAverageHiddenRating, 1_000);
    assert.equal(matchBefore.config.questionSelection.difficultyBand ?? null, null);

    await joinReadyOpen(context);
    await playTwentyQuestions(context);

    const match = await adminRequest(`competitiveV2/matches/${context.matchId}`);
    assert.equal(match.private.phase, PHASE.SETTLED);
    assert.equal(match.private.currentQuestionIndex, 19);
    assert.equal(match.private.settlement.status, "SETTLED");
    assert.equal(Object.hasOwn(match.private.settlement, "playerResults"), false);
    assert.equal(match.public.phase, PHASE.SETTLED);

    const settlement = await adminRequest(
      `competitiveV2/matchmaking/private/settlements/${context.matchId}`
    );
    assert.equal(settlement.status, "SETTLED");
    assert.equal(Object.keys(settlement.playerResults).length, 2);

    const profiles = await adminRequest("competitiveV2/matchmaking/private/profiles");
    for (const client of context.clients) {
      const result = settlement.playerResults[client.uid];
      assert.ok(result);
      assert.equal(profiles[client.uid].competitive.stats.matchesPlayed, 1);
      assert.equal(profiles[client.uid].currentSession.state, "FINISHED");
      assert.equal(profiles[client.uid].currentSession.matchId, undefined);
      const publicValue = await projection(client);
      assert.equal(publicValue.state, "NOT_QUEUED");
      assert.ok(publicValue.competitive.currentTier);
      assert.equal(publicValue.competitive.stats.matchesPlayed, 1);
      assert.equal(Object.hasOwn(publicValue.competitive, "hiddenRating"), false);
    }
    assert.equal(profiles[context.clients[0].uid].competitive.stats.totalWins, 1);
    assert.equal(await adminRequest(`competitiveV2/presence/${context.matchId}`), null);
    assert.equal(Object.keys(profiles).length, Object.keys(before).length);

    const ratingBeforeRetry = profiles[context.clients[0].uid].competitive.hiddenRating;
    const retry = await reconcile(context.clients[0], context.sessions[0], "after-settled");
    assert.equal(retry.rejectionCode, "STALE_ACTIVE_MATCH_SESSION");
    const afterRetry = await adminRequest(
      `competitiveV2/matchmaking/private/profiles/${context.clients[0].uid}/competitive`
    );
    assert.equal(afterRetry.hiddenRating, ratingBeforeRetry);
    assert.equal(afterRetry.stats.matchesPlayed, 1);

    await assertFails(set(ref(
      context.clients[0].database,
      `competitiveV2/matchmaking/public/${context.clients[0].uid}/competitive/currentTier`
    ), "RATING_BATTLE"));
    await assertFails(set(ref(
      context.clients[0].database,
      `competitiveV2/matchmaking/private/profiles/${context.clients[0].uid}/competitive/hiddenRating`
    ), 9_999));
  });
});
