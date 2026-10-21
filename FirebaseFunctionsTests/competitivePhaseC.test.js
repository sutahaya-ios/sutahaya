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
  ref,
  serverTimestamp,
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
  }, `phase-c-${randomUUID()}`);
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

async function matchmaking(client, value) {
  return (await httpsCallable(client.functions, "competitiveMatchmaking")(value)).data;
}

async function coreIntent(client, value) {
  return (await httpsCallable(client.functions, "competitiveIntent")(value)).data;
}

async function reconcile(client, session, suffix) {
  return (await httpsCallable(client.functions, "competitiveReconcileMatch")({
    intentId: `reconcile-${suffix}-${randomUUID()}`,
    type: "reconcile",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-c-emulator",
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    matchId: session.matchId,
    lastSeenServerSequence: 0,
    payload: {},
  })).data;
}

function matchEnvelope(session, type, suffix, overrides = {}) {
  return {
    intentId: `${type}-${suffix}-${randomUUID()}`,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-c-emulator",
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    matchId: session.matchId,
    lastSeenServerSequence: 0,
    payload: {},
    ...overrides,
  };
}

async function projection(client) {
  return (await get(ref(
    client.database,
    `competitiveV2/matchmaking/public/${client.uid}`
  ))).val();
}

async function queueMatch(humanCount, { waitRealFiveSeconds = false } = {}) {
  const clients = await Promise.all(Array.from({ length: humanCount }, () => createClient()));
  const joins = await Promise.all(clients.map((client) => matchmaking(client, {
    intentId: `join-${randomUUID()}`,
    type: "joinQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-c-emulator",
    payload: {},
  })));
  if (humanCount < 4) {
    if (waitRealFiveSeconds) {
      await delay(5_050);
    } else {
      const oldQueuedAt = Date.now() - 5_050;
      await Promise.all(clients.map((client) => adminRequest(
        `competitiveV2/matchmaking/private/queue/${client.uid}/queuedAtEpochMs`,
        "PUT",
        oldQueuedAt
      )));
    }
    await matchmaking(clients[0], {
      intentId: `check-${randomUUID()}`,
      type: "checkQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-emulator",
      sessionId: joins[0].sessionId,
      sessionEpoch: joins[0].sessionEpoch,
      payload: {},
    });
  }
  const sessions = await Promise.all(clients.map((client) => waitFor(async () => {
    const value = await projection(client);
    return value?.state === "WAITING_PLAYERS" ? value : null;
  }, "WAITING_PLAYERS")));
  assert.equal(new Set(sessions.map((session) => session.matchId)).size, 1);
  return { clients, sessions, matchId: sessions[0].matchId };
}

async function joinReadyOpen(clients, sessions) {
  for (const [index, client] of clients.entries()) {
    const session = sessions[index];
    const joined = await coreIntent(client, matchEnvelope(session, "joinMatch", index, {
      payload: { assignmentTicket: session.assignmentTicket },
    }));
    assert.equal(joined.status, "ACCEPTED");
  }
  for (const [index, client] of clients.entries()) {
    assert.equal((await coreIntent(
      client,
      matchEnvelope(sessions[index], "ready", index)
    )).status, "ACCEPTED");
  }
  await delay(5);
  await reconcile(clients[0], sessions[0], "countdown");
}

async function playTwentyQuestions(clients, sessions, matchId) {
  const seenNPCOutcomes = new Set();
  for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
    let state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    assert.equal(state.phase, PHASE.QUESTION_OPEN);
    assert.equal(state.currentQuestionIndex, questionIndex);
    await Promise.all(clients.map((client, index) => coreIntent(
      client,
      matchEnvelope(sessions[index], "submitAnswer", `${questionIndex}-${index}`, {
        questionId: state.currentQuestion.questionId,
        stateVersion: state.stateVersion,
        payload: { answerId: state.currentQuestion.correctAnswerId },
      })
    )));
    if (clients.length < 4) await delay(210);
    state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    if (state.phase === PHASE.QUESTION_OPEN) {
      await reconcile(clients[0], sessions[0], `close-${questionIndex}`);
      state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    }
    assert.equal(state.phase, PHASE.QUESTION_RESULT);
    const result = state.currentQuestion.result;
    for (const uid of result.correctUIDs || []) {
      const correctRank = result.correctUIDs.indexOf(uid);
      assert.equal(result.scoreDeltas[uid], [20, 10, 5, 1][correctRank] ?? 1);
      if (uid.startsWith("npc:")) seenNPCOutcomes.add("correct");
    }
    for (const uid of result.wrongUIDs || []) {
      assert.equal(result.scoreDeltas[uid], -10);
      if (uid.startsWith("npc:")) seenNPCOutcomes.add("wrong");
    }
    for (const uid of result.unansweredUIDs || []) {
      assert.equal(result.scoreDeltas[uid], 0);
      if (uid.startsWith("npc:")) seenNPCOutcomes.add("unanswered");
    }
    await delay(3);
    await reconcile(clients[0], sessions[0], `advance-${questionIndex}`);
    if (questionIndex < 19) {
      await reconcile(clients[0], sessions[0], `open-${questionIndex + 1}`);
    }
  }
  const finalState = await adminRequest(`competitiveV2/matches/${matchId}/private`);
  assert.equal(finalState.phase, PHASE.SETTLED);
  assert.equal(finalState.currentQuestionIndex, 19);
  assert.equal(Object.keys(finalState.matchResult.finalScores).length, 4);
  if (clients.length < 4) {
    assert.deepEqual(seenNPCOutcomes, new Set(["correct", "wrong", "unanswered"]));
  }
  await Promise.all(clients.map((client) => waitFor(async () => {
    const value = await projection(client);
    return value?.state === "NOT_QUEUED" ? value : null;
  }, "released session")));
}

async function finishMatchFromCurrentState(client, session, matchId) {
  for (let step = 0; step < 100; step += 1) {
    const state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    if (state.phase === PHASE.SETTLED) return state;
    if (state.phase === PHASE.COUNTDOWN) {
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/countdownEndsAtEpochMs`,
        "PUT",
        Date.now() - 1
      );
    } else if (state.phase === PHASE.QUESTION_OPEN) {
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/currentQuestion/deadlineEpochMs`,
        "PUT",
        Date.now() - 1
      );
    } else if (state.phase === PHASE.QUESTION_RESULT) {
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/resultEndsAtEpochMs`,
        "PUT",
        Date.now() - 1
      );
    }
    await reconcile(client, session, `finish-${step}`);
  }
  throw new Error(`Match did not settle: ${matchId}`);
}

describe("Competitive Phase C Emulator", () => {
  it("completes 20 questions for 1-4 humans with Bronze NPC fill and settlement", async () => {
    for (let humanCount = 1; humanCount <= 4; humanCount += 1) {
      const queued = await queueMatch(humanCount, { waitRealFiveSeconds: humanCount === 1 });
      const match = await adminRequest(`competitiveV2/matches/${queued.matchId}`);
      const participants = Object.values(match.private.participants);
      assert.equal(participants.length, 4);
      assert.equal(participants.filter((participant) => participant.kind === "HUMAN").length, humanCount);
      assert.equal(participants.filter((participant) => participant.kind === "NPC").length, 4 - humanCount);
      await adminRequest(`competitiveV2/matches/${queued.matchId}/private/config`, "PATCH", {
        countdownDurationMs: 1,
        questionDurationMs: 200,
        resultDurationMs: 1,
        npcSkillInput: {
          profileVersion: "phase-c-fixed-test-1",
          reactionBaseMs: 5,
        },
      });
      await joinReadyOpen(queued.clients, queued.sessions);
      await playTwentyQuestions(queued.clients, queued.sessions, queued.matchId);
    }
  });

  it("handles reconnect, timeout forfeit, presence Rules, and Room A to B fencing", async () => {
    const roomA = await queueMatch(1);
    await adminRequest(`competitiveV2/matches/${roomA.matchId}/private/config`, "PATCH", {
      countdownDurationMs: 1,
      questionDurationMs: 500,
      resultDurationMs: 1,
      npcSkillInput: {
        profileVersion: "phase-c-fixed-test-1",
        reactionBaseMs: 5,
      },
    });
    await joinReadyOpen(roomA.clients, roomA.sessions);
    const client = roomA.clients[0];
    const sessionA = roomA.sessions[0];
    const presencePath = `competitiveV2/presence/${roomA.matchId}/${client.uid}`;
    const disconnected = {
      status: "DISCONNECTED",
      sessionId: sessionA.sessionId,
      sessionEpoch: sessionA.sessionEpoch,
      updatedAtEpochMs: serverTimestamp(),
    };
    await assertSucceeds(set(ref(client.database, presencePath), disconnected));
    await assertFails(get(ref(client.database, presencePath)));
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${roomA.matchId}/public/participants/${client.uid}`
      );
      return participant?.status === "RECONNECTING";
    }, "RECONNECTING projection");

    const open = await adminRequest(`competitiveV2/matches/${roomA.matchId}/private`);
    const blockedAnswer = await coreIntent(client, matchEnvelope(sessionA, "submitAnswer", "offline", {
      questionId: open.currentQuestion.questionId,
      stateVersion: open.stateVersion,
      payload: { answerId: open.currentQuestion.correctAnswerId },
    }));
    assert.equal(blockedAnswer.rejectionCode, "PLAYER_RECONNECTING");

    await adminRequest(
      `competitiveV2/matches/${roomA.matchId}/private/currentQuestion/deadlineEpochMs`,
      "PUT",
      Date.now() - 1
    );
    await reconcile(client, sessionA, "progress-while-disconnected");
    let roomAState = await adminRequest(`competitiveV2/matches/${roomA.matchId}/private`);
    assert.equal(roomAState.phase, PHASE.QUESTION_RESULT);
    assert.ok(roomAState.currentQuestion.result.unansweredUIDs.includes(client.uid));
    assert.equal(roomAState.currentQuestion.result.scoreDeltas[client.uid], 0);
    await adminRequest(
      `competitiveV2/matches/${roomA.matchId}/private/resultEndsAtEpochMs`,
      "PUT",
      Date.now() - 1
    );
    await reconcile(client, sessionA, "advance-while-disconnected");
    await reconcile(client, sessionA, "open-after-disconnected-question");

    await assertSucceeds(set(ref(client.database, presencePath), {
      ...disconnected,
      status: "CONNECTED",
      updatedAtEpochMs: serverTimestamp(),
    }));
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${roomA.matchId}/public/participants/${client.uid}`
      );
      return participant?.status === "CONNECTED";
    }, "CONNECTED projection");
    const roomARetryEnvelope = matchEnvelope(sessionA, "reconnect", "retry-source");
    assert.equal((await coreIntent(client, roomARetryEnvelope)).status, "ACCEPTED");
    roomAState = await adminRequest(`competitiveV2/matches/${roomA.matchId}/private`);
    assert.equal(roomAState.phase, PHASE.QUESTION_OPEN);
    assert.equal(roomAState.currentQuestionIndex, 1);

    await assertSucceeds(set(ref(client.database, presencePath), disconnected));
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${roomA.matchId}/private/participants/${client.uid}`
      );
      return participant?.status === "RECONNECTING";
    }, "second disconnect");
    await adminRequest(
      `competitiveV2/matches/${roomA.matchId}/private/participants/${client.uid}/reconnectDeadlineEpochMs`,
      "PUT",
      Date.now() - 1
    );
    await reconcile(client, sessionA, "expire-grace");
    const forfeited = await adminRequest(
      `competitiveV2/matches/${roomA.matchId}/private/participants/${client.uid}`
    );
    assert.equal(forfeited.status, "FORFEITED");
    assert.equal(forfeited.forfeitReason, "RECONNECT_TIMEOUT");

    const attacker = await createClient();
    await assertFails(set(ref(attacker.database, presencePath), disconnected));
    assert.equal(
      (await finishMatchFromCurrentState(client, sessionA, roomA.matchId)).phase,
      PHASE.SETTLED
    );

    const joinB = await matchmaking(client, {
      intentId: `join-b-${randomUUID()}`,
      type: "joinQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-emulator",
      payload: {},
    });
    await adminRequest(
      `competitiveV2/matchmaking/private/queue/${client.uid}/queuedAtEpochMs`,
      "PUT",
      Date.now() - 5_050
    );
    await matchmaking(client, {
      intentId: `check-b-${randomUUID()}`,
      type: "checkQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-emulator",
      sessionId: joinB.sessionId,
      sessionEpoch: joinB.sessionEpoch,
      payload: {},
    });
    const sessionB = await waitFor(async () => {
      const value = await projection(client);
      return value?.state === "WAITING_PLAYERS" && value.matchId !== roomA.matchId
        ? value
        : null;
    }, "Room B");

    const roomBBefore = await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private`);
    const projectionBefore = await projection(client);
    const staleRoomAIntents = [
      matchEnvelope(sessionA, "ready", "room-a-stale-ready"),
      matchEnvelope(sessionA, "forfeit", "room-a-stale-forfeit"),
      matchEnvelope(sessionA, "submitAnswer", "room-a-stale-answer", {
        questionId: open.currentQuestion.questionId,
        stateVersion: open.stateVersion,
        payload: { answerId: open.currentQuestion.correctAnswerId },
      }),
      roomARetryEnvelope,
    ];
    for (const staleIntent of staleRoomAIntents) {
      const staleRoomA = await coreIntent(client, staleIntent);
      assert.equal(staleRoomA.rejectionCode, "STALE_ACTIVE_MATCH_SESSION");
    }
    assert.deepEqual(
      await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private`),
      roomBBefore
    );
    assert.deepEqual(await projection(client), projectionBefore);

    await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private/config`, "PATCH", {
      countdownDurationMs: 1,
      questionDurationMs: 500,
      resultDurationMs: 1,
      npcSkillInput: {
        profileVersion: "phase-c-fixed-test-1",
        reactionBaseMs: 5,
      },
    });
    await joinReadyOpen([client], [sessionB]);
    const scoreBefore = (await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    )) || 0;
    const explicitForfeitEnvelope = matchEnvelope(sessionB, "forfeit", "explicit");
    const explicitForfeit = await coreIntent(client, explicitForfeitEnvelope);
    assert.equal(explicitForfeit.status, "ACCEPTED");
    assert.equal((await coreIntent(client, explicitForfeitEnvelope)).status, "DUPLICATE");
    const roomBParticipant = await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/participants/${client.uid}`
    );
    assert.equal(roomBParticipant.status, "FORFEITED");
    assert.equal(roomBParticipant.forfeitReason, "EXPLICIT_FORFEIT");
    assert.equal(await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    ), scoreBefore);
    const roomBOpen = await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private`);
    assert.equal((await coreIntent(client, matchEnvelope(sessionB, "submitAnswer", "after-forfeit", {
      questionId: roomBOpen.currentQuestion.questionId,
      stateVersion: roomBOpen.stateVersion,
      payload: { answerId: roomBOpen.currentQuestion.correctAnswerId },
    }))).rejectionCode, "NOT_ACTIVE_PLAYER");
    assert.equal(
      (await coreIntent(client, matchEnvelope(sessionB, "reconnect", "after-forfeit"))).rejectionCode,
      "PLAYER_FORFEITED"
    );
    assert.equal(
      (await finishMatchFromCurrentState(client, sessionB, sessionB.matchId)).phase,
      PHASE.SETTLED
    );
    assert.equal(await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    ), scoreBefore);
  });
});
