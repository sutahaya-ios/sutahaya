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
  remove,
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

function waitForPublicState(client, matchId, predicate, description, timeoutMs = 10_000) {
  return new Promise((resolve, reject) => {
    const reference = ref(client.database, `competitiveV2/matches/${matchId}/public`);
    let unsubscribe = () => {};
    const timer = setTimeout(() => {
      unsubscribe();
      reject(new Error(`Timed out waiting for ${description}`));
    }, timeoutMs);
    unsubscribe = onValue(reference, (snapshot) => {
      const value = snapshot.val();
      if (!predicate(value)) return;
      clearTimeout(timer);
      unsubscribe();
      resolve(value);
    }, (error) => {
      clearTimeout(timer);
      unsubscribe();
      reject(error);
    });
  });
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

function presencePayload(session, connected) {
  const value = {
    connected,
    matchId: session.matchId,
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    updatedAtEpochMs: serverTimestamp(),
  };
  if (!connected) value.disconnectedAtEpochMs = serverTimestamp();
  return value;
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
  const initialState = await adminRequest(`competitiveV2/matches/${matchId}/private`);
  const expectedScores = Object.fromEntries(
    initialState.participantOrder.map((uid) => [uid, 0])
  );
  for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
    let state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    assert.equal(state.phase, PHASE.QUESTION_OPEN);
    assert.equal(state.currentQuestionIndex, questionIndex);
    const npcUIDs = state.participantOrder.filter(
      (uid) => state.participants[uid].kind === "NPC"
    );
    if (npcUIDs.length > 0) {
      const existingPlans = state.currentQuestion.npcPlans || {};
      const now = Date.now();
      const acceleratedPlans = questionIndex === 2 ? {} : Object.fromEntries(
        Object.entries(existingPlans).map(([uid, plan], index) => [uid, {
          ...plan,
          acceptedAtEpochMs: now + 10 + index * 10,
        }])
      );
      if (questionIndex <= 1) {
        const answerId = questionIndex === 0
          ? state.currentQuestion.correctAnswerId
          : state.currentQuestion.choices.find(
            (choice) => choice.answerId !== state.currentQuestion.correctAnswerId
          ).answerId;
        acceleratedPlans[npcUIDs[0]] = {
          uid: npcUIDs[0],
          eventId: `phase-c-npc-outcome-${questionIndex}`,
          questionId: state.currentQuestion.questionId,
          answerId,
          acceptedAtEpochMs: now + 10,
          status: "ACCEPTED",
          source: "SERVER_NPC",
        };
      }
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/currentQuestion/npcPlans`,
        "PUT",
        acceleratedPlans
      );
    }
    await Promise.all(clients.map((client, index) => coreIntent(
      client,
      matchEnvelope(sessions[index], "submitAnswer", `${questionIndex}-${index}`, {
        questionId: state.currentQuestion.questionId,
        stateVersion: state.stateVersion,
        payload: { answerId: state.currentQuestion.correctAnswerId },
      })
    )));
    if (clients.length < 4) await delay(60);
    state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    if (state.phase === PHASE.QUESTION_OPEN) {
      await adminRequest(
        `competitiveV2/matches/${matchId}/private/currentQuestion/deadlineEpochMs`,
        "PUT",
        Date.now() - 1
      );
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
    for (const uid of initialState.participantOrder) {
      expectedScores[uid] += result.scoreDeltas[uid];
      assert.equal(result.cumulativeScores[uid], expectedScores[uid]);
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
  assert.deepEqual(finalState.matchResult.finalScores, expectedScores);
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
        questionDurationMs: 8_000,
        resultDurationMs: 1,
        npcSkillInput: {
          profileVersion: "shared-seven-npc-v1",
          strengthProfileId: "STRONG",
          accuracyPermille: 600,
        },
      });
      await joinReadyOpen(queued.clients, queued.sessions);
      await playTwentyQuestions(queued.clients, queued.sessions, queued.matchId);
    }
  });

  it("projects Human and multiple NPC answered states during QUESTION_OPEN", async () => {
    const queued = await queueMatch(2);
    await adminRequest(`competitiveV2/matches/${queued.matchId}/private/config`, "PATCH", {
      countdownDurationMs: 1,
      questionDurationMs: 8_000,
      resultDurationMs: 1,
      npcSkillInput: {
        profileVersion: "shared-seven-npc-v1",
        strengthProfileId: "NORMAL",
        accuracyPermille: 500,
      },
    });
    await joinReadyOpen(queued.clients, queued.sessions);

    let privateState = await adminRequest(
      `competitiveV2/matches/${queued.matchId}/private`
    );
    const humanUIDs = privateState.participantOrder.filter(
      (uid) => privateState.participants[uid].kind === "HUMAN"
    );
    const npcUIDs = privateState.participantOrder.filter(
      (uid) => privateState.participants[uid].kind === "NPC"
    );
    const now = Date.now();
    const controlledPlans = Object.fromEntries(npcUIDs.map((uid, index) => [uid, {
      uid,
      eventId: `phase-c-realtime-npc-${index}`,
      questionId: privateState.currentQuestion.questionId,
      answerId: privateState.currentQuestion.choices[index].answerId,
      acceptedAtEpochMs: now + 100 + index * 200,
      status: "ACCEPTED",
      source: "SERVER_NPC",
    }]));
    await adminRequest(
      `competitiveV2/matches/${queued.matchId}/private/currentQuestion/npcPlans`,
      "PUT",
      controlledPlans
    );
    privateState = await adminRequest(`competitiveV2/matches/${queued.matchId}/private`);
    const orderedNPCPlans = Object.entries(privateState.currentQuestion.npcPlans)
      .sort((left, right) => left[1].acceptedAtEpochMs - right[1].acceptedAtEpochMs);
    assert.equal(humanUIDs.length, 2);
    assert.equal(orderedNPCPlans.length, 2);
    await delay(Math.max(
      0,
      orderedNPCPlans[0][1].acceptedAtEpochMs - Date.now() + 25
    ));

    const firstSeenByAllClients = queued.clients.map((client) => waitForPublicState(
      client,
      queued.matchId,
      (state) => state?.phase === PHASE.QUESTION_OPEN
        && state.participants?.[orderedNPCPlans[0][0]]?.answered === true
        && state.participants?.[orderedNPCPlans[1][0]]?.answered === false,
      "first NPC answered projection"
    ));
    await reconcile(queued.clients[0], queued.sessions[0], "first-npc-answered");
    const firstStates = await Promise.all(firstSeenByAllClients);
    for (const state of firstStates) {
      assert.equal(state.questionResult == null, true);
      assert.equal(state.currentQuestion.correctAnswerId, undefined);
      assert.equal(state.participants[orderedNPCPlans[0][0]].answerId, undefined);
      for (const uid of humanUIDs) assert.equal(state.participants[uid].answered, false);
    }

    await delay(Math.max(
      0,
      orderedNPCPlans[1][1].acceptedAtEpochMs - Date.now() + 25
    ));

    const secondSeenByAllClients = queued.clients.map((client) => waitForPublicState(
      client,
      queued.matchId,
      (state) => state?.phase === PHASE.QUESTION_OPEN
        && state.participants?.[orderedNPCPlans[0][0]]?.answered === true
        && state.participants?.[orderedNPCPlans[1][0]]?.answered === true,
      "second NPC answered projection"
    ));
    await reconcile(queued.clients[1], queued.sessions[1], "second-npc-answered");
    const secondStates = await Promise.all(secondSeenByAllClients);
    for (const state of secondStates) {
      assert.equal(state.questionResult == null, true);
      assert.equal(state.currentQuestion.correctAnswerId, undefined);
    }

    privateState = await adminRequest(`competitiveV2/matches/${queued.matchId}/private`);
    assert.equal(privateState.phase, PHASE.QUESTION_OPEN);
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
    const connected = presencePayload(sessionA, true);
    const disconnected = presencePayload(sessionA, false);

    await assertSucceeds(set(ref(client.database, presencePath), connected));
    assert.equal((await adminRequest(presencePath)).connected, true);
    await assertSucceeds(set(ref(client.database, presencePath), disconnected));
    await assertFails(get(ref(client.database, presencePath)));
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${roomA.matchId}/public/participants/${client.uid}`
      );
      return participant?.status === "RECONNECTING";
    }, "RECONNECTING projection");

    await assertFails(set(ref(client.database, presencePath), {
      ...disconnected,
      sessionId: `${sessionA.sessionId}-stale`,
    }));
    await assertFails(set(ref(client.database, presencePath), {
      ...disconnected,
      sessionEpoch: sessionA.sessionEpoch + 1,
    }));
    const attacker = await createClient();
    await assertFails(set(ref(attacker.database, presencePath), disconnected));
    await assertFails(remove(ref(client.database, presencePath)));
    assert.equal((await adminRequest(presencePath)).connected, false);

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

    await assertSucceeds(set(ref(client.database, presencePath), connected));
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

    const acceptedAnswer = await coreIntent(client, matchEnvelope(
      sessionA,
      "submitAnswer",
      "answered-projection",
      {
        questionId: roomAState.currentQuestion.questionId,
        stateVersion: roomAState.stateVersion,
        payload: { answerId: roomAState.currentQuestion.correctAnswerId },
      }
    ));
    assert.equal(acceptedAnswer.status, "ACCEPTED");
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${roomA.matchId}/public/participants/${client.uid}`
      );
      return participant?.answered === true;
    }, "answered projection after accepted answer");

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

    const roomBPresencePath = `competitiveV2/presence/${sessionB.matchId}/${client.uid}`;
    await assertSucceeds(set(
      ref(client.database, roomBPresencePath),
      presencePayload(sessionB, true)
    ));
    const roomBPresenceBefore = await adminRequest(roomBPresencePath);
    await assertFails(set(
      ref(client.database, presencePath),
      presencePayload(sessionA, false)
    ));
    assert.deepEqual(await adminRequest(roomBPresencePath), roomBPresenceBefore);

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
    await assertSucceeds(set(
      ref(client.database, roomBPresencePath),
      presencePayload(sessionB, false)
    ));
    await waitFor(async () => {
      const participant = await adminRequest(
        `competitiveV2/matches/${sessionB.matchId}/private/participants/${client.uid}`
      );
      return participant?.status === "RECONNECTING";
    }, "Room B legitimate disconnect");
    assert.equal(
      (await coreIntent(client, matchEnvelope(sessionB, "reconnect", "before-explicit-forfeit"))).status,
      "ACCEPTED"
    );
    await assertSucceeds(set(
      ref(client.database, roomBPresencePath),
      presencePayload(sessionB, true)
    ));
    assert.equal((await adminRequest(roomBPresencePath)).connected, true);
    const scoreBefore = (await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    )) || 0;
    const explicitForfeitEnvelope = matchEnvelope(sessionB, "forfeit", "explicit");
    const explicitForfeit = await coreIntent(client, explicitForfeitEnvelope);
    assert.equal(explicitForfeit.status, "ACCEPTED");
    assert.equal((await coreIntent(client, explicitForfeitEnvelope)).status, "DUPLICATE");
    assert.equal(await adminRequest(roomBPresencePath), null);
    await assertFails(set(
      ref(client.database, roomBPresencePath),
      presencePayload(sessionB, true)
    ));
    const roomBParticipant = await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/participants/${client.uid}`
    );
    assert.equal(roomBParticipant.status, "FORFEITED");
    assert.equal(roomBParticipant.forfeitReason, "EXPLICIT_FORFEIT");
    assert.equal(roomBParticipant.joined, undefined);
    assert.equal(roomBParticipant.ready, undefined);
    assert.equal(roomBParticipant.sessionId, sessionB.sessionId);
    assert.equal(await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/public/participants/${client.uid}`
    ), null);
    assert.ok((await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/public/forfeitedUIDs`
    )).includes(client.uid));
    assert.equal(await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    ), scoreBefore);
    const roomBOpen = await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private`);
    assert.equal((await coreIntent(client, matchEnvelope(sessionB, "submitAnswer", "after-forfeit", {
      questionId: roomBOpen.currentQuestion.questionId,
      stateVersion: roomBOpen.stateVersion,
      payload: { answerId: roomBOpen.currentQuestion.correctAnswerId },
    }))).rejectionCode, "STALE_ACTIVE_MATCH_SESSION");
    assert.equal(
      (await coreIntent(client, matchEnvelope(sessionB, "reconnect", "after-forfeit"))).rejectionCode,
      "STALE_ACTIVE_MATCH_SESSION"
    );
    const releasedProjection = await projection(client);
    assert.equal(releasedProjection.state, "NOT_QUEUED");
    assert.ok(releasedProjection.cooldownEndsAtEpochMs > releasedProjection.updatedAtEpochMs);
    const earlyRequeue = await matchmaking(client, {
      intentId: `requeue-early-${randomUUID()}`,
      type: "joinQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-emulator",
      payload: {},
    });
    assert.equal(earlyRequeue.rejectionCode, "FORFEIT_COOLDOWN_ACTIVE");

    await adminRequest(
      `competitiveV2/matchmaking/private/profiles/${client.uid}/explicitForfeitCooldown/cooldownEndsAtEpochMs`,
      "PUT",
      Date.now() - 1
    );
    const requeue = await matchmaking(client, {
      intentId: `requeue-after-cooldown-${randomUUID()}`,
      type: "joinQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-c-emulator",
      payload: {},
    });
    assert.equal(requeue.status, "ACCEPTED");
    assert.notEqual(requeue.sessionId, sessionB.sessionId);
    assert.ok(requeue.sessionEpoch > sessionB.sessionEpoch);
    assert.equal(
      (await adminRequest(`competitiveV2/matches/${sessionB.matchId}/private`)).phase,
      PHASE.QUESTION_OPEN
    );
    assert.equal(await adminRequest(
      `competitiveV2/matches/${sessionB.matchId}/private/scores/${client.uid}`
    ), scoreBefore);
  });
});
