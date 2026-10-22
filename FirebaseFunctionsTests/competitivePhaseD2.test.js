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
const {
  RATING_CONFIG,
  TIER,
  initialCompetitiveProfile,
  tierForRating,
} = require("../functions/competitive/rating");

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

async function waitFor(predicate, description, timeoutMs = 15_000) {
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
  }, `phase-d2-${randomUUID()}`);
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
    clientBuild: "phase-d2-emulator",
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

async function seedProfile(client, {
  rating,
  tier = tierForRating(rating),
  platinumSeasonMatches = 0,
  platinumSeasonWins = 0,
}) {
  const nowEpochMs = Date.now();
  const competitive = initialCompetitiveProfile(nowEpochMs);
  competitive.hiddenRating = rating;
  competitive.currentTier = tier;
  competitive.ratingBattle = tier === TIER.RATING_BATTLE;
  competitive.season.platinumSeasonMatches = platinumSeasonMatches;
  competitive.season.platinumSeasonWins = platinumSeasonWins;
  await adminRequest(`competitiveV2/matchmaking/private/profiles/${client.uid}`, "PUT", {
    uid: client.uid,
    createdAtEpochMs: nowEpochMs,
    accountStatus: "ACTIVE",
    accountType: "ANONYMOUS",
    protocolVersion: PROTOCOL_VERSION,
    intentResults: {},
    competitive,
  });
}

async function createMatch(playerSpecs, npcWaitMs = null) {
  const clients = await Promise.all(playerSpecs.map(() => createClient()));
  await Promise.all(clients.map((client, index) => seedProfile(client, playerSpecs[index])));
  const joins = [];
  for (const client of clients) {
    joins.push(await matchmaking(client, {
      intentId: `join-${randomUUID()}`,
      type: "joinQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-d2-emulator",
      payload: {},
    }));
  }
  if (clients.length < 4) {
    const oldQueuedAt = Date.now() - npcWaitMs - 100;
    await Promise.all(clients.map((client) => adminRequest(
      `competitiveV2/matchmaking/private/queue/${client.uid}/queuedAtEpochMs`,
      "PUT",
      oldQueuedAt
    )));
    await matchmaking(clients[0], {
      intentId: `check-${randomUUID()}`,
      type: "checkQueue",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-d2-emulator",
      sessionId: joins[0].sessionId,
      sessionEpoch: joins[0].sessionEpoch,
      payload: {},
    });
  }
  const sessions = await Promise.all(clients.map((client) => waitFor(async () => {
    const value = await projection(client);
    return value?.state === "WAITING_PLAYERS" ? value : null;
  }, "Phase D-2 match assignment")));
  assert.equal(new Set(sessions.map((value) => value.matchId)).size, 1);
  return { clients, sessions, matchId: sessions[0].matchId };
}

async function joinReadyOpen(context) {
  const { clients, sessions, matchId } = context;
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

async function playTwentyQuestions(context, winnerIndex = 0) {
  const { clients, sessions, matchId } = context;
  await joinReadyOpen(context);
  const firstPublicQuestion = (await get(ref(
    clients[0].database,
    `competitiveV2/matches/${matchId}/public/currentQuestion`
  ))).val();
  assert.equal(Object.hasOwn(firstPublicQuestion, "correctAnswerId"), false);
  assert.equal(Object.hasOwn(firstPublicQuestion, "canonicalId"), false);
  assert.equal(Object.hasOwn(firstPublicQuestion, "difficulty"), false);

  for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
    let state = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    assert.equal(state.phase, PHASE.QUESTION_OPEN);
    const wrongAnswerId = state.currentQuestion.choices.find(
      (choice) => choice.answerId !== state.currentQuestion.correctAnswerId
    ).answerId;
    for (const [index, client] of clients.entries()) {
      const acknowledgement = await call(
        client,
        "competitiveIntent",
        envelope(sessions[index], "submitAnswer", `${questionIndex}-${index}`, {
          questionId: state.currentQuestion.questionId,
          stateVersion: state.stateVersion,
          payload: {
            answerId: index === winnerIndex
              ? state.currentQuestion.correctAnswerId
              : wrongAnswerId,
          },
        })
      );
      assert.equal(acknowledgement.status, "ACCEPTED");
    }
    await delay(8);
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
  return waitFor(async () => {
    const value = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    return value?.phase === PHASE.SETTLED ? value : null;
  }, "Phase D-2 settlement");
}

async function assertFullScenario({
  name,
  playerSpecs,
  npcWaitMs,
  expectedHumans,
  expectedTier,
  minimumDifficulty,
  maximumDifficulty,
  expectedHumanWeight,
}) {
  const context = await createMatch(playerSpecs, npcWaitMs);
  const before = await adminRequest(`competitiveV2/matches/${context.matchId}/private`);
  const participants = Object.values(before.participants);
  assert.equal(participants.filter((value) => value.kind === "HUMAN").length, expectedHumans, name);
  assert.equal(before.questionInstances.length, 20, name);
  assert.equal(new Set(before.questionInstances.map((question) => question.canonicalId)).size, 20, name);
  assert.ok(before.questionInstances.every((question) => (
    question.difficulty >= minimumDifficulty && question.difficulty <= maximumDifficulty
  )), name);
  assert.equal(before.config.questionSelection.matchTier, expectedTier, name);
  assert.deepEqual(before.config.questionSelection.difficultyBand, {
    minimum: minimumDifficulty,
    maximum: maximumDifficulty,
  }, name);
  await playTwentyQuestions(context);
  const settlement = await adminRequest(
    `competitiveV2/matchmaking/private/settlements/${context.matchId}`
  );
  assert.equal(settlement.status, "SETTLED", name);
  for (const result of Object.values(settlement.playerResults)) {
    assert.equal(result.humanWeight, expectedHumanWeight, name);
  }
  return context;
}

async function forceSettlement(playerSpecs, ranks) {
  const context = await createMatch(playerSpecs);
  const privateState = await adminRequest(`competitiveV2/matches/${context.matchId}/private`);
  privateState.phase = PHASE.MATCH_FINISHED;
  const participantOrder = privateState.participantOrder;
  privateState.matchResult = {
    matchId: context.matchId,
    outcome: "COMPLETED",
    finalScores: Object.fromEntries(participantOrder.map((uid) => [uid, 0])),
    ranks: Object.fromEntries(participantOrder.map(
      (uid, index) => [uid, ranks[index]]
    )),
    winnerUIDs: participantOrder.filter((_, index) => ranks[index] === 1),
    forfeitedUIDs: [],
    finishedAtEpochMs: Date.now(),
    configVersion: privateState.configVersion,
  };
  delete privateState.settlement;
  await adminRequest(`competitiveV2/matches/${context.matchId}/private`, "PUT", privateState);
  await reconcile(context.clients[0], context.sessions[0], "forced-settlement");
  const settlement = await waitFor(
    () => adminRequest(`competitiveV2/matchmaking/private/settlements/${context.matchId}`),
    "forced Phase D-2 settlement"
  );
  return { context, settlement };
}

describe("Competitive Phase D-2 Emulator", () => {
  it("completes Bronze/Silver NPC and Gold/Platinum human-only 20-question matches", async () => {
    const scenarios = [
      {
        name: "Bronze Human1 + NPC3",
        playerSpecs: [{ rating: 1_000, tier: TIER.BRONZE }],
        npcWaitMs: 5_000,
        expectedHumans: 1,
        expectedTier: TIER.BRONZE,
        minimumDifficulty: 1,
        maximumDifficulty: 2,
        expectedHumanWeight: 0.5,
      },
      {
        name: "Silver Human2 + NPC2",
        playerSpecs: [
          { rating: 1_200, tier: TIER.SILVER },
          { rating: 1_300, tier: TIER.SILVER },
        ],
        npcWaitMs: 10_000,
        expectedHumans: 2,
        expectedTier: TIER.SILVER,
        minimumDifficulty: 2,
        maximumDifficulty: 3,
        expectedHumanWeight: 2 / 3,
      },
      {
        name: "Gold Human4",
        playerSpecs: Array.from({ length: 4 }, () => ({ rating: 1_500, tier: TIER.GOLD })),
        expectedHumans: 4,
        expectedTier: TIER.GOLD,
        minimumDifficulty: 3,
        maximumDifficulty: 4,
        expectedHumanWeight: 1,
      },
      {
        name: "Platinum Human4",
        playerSpecs: Array.from({ length: 4 }, () => ({ rating: 1_700, tier: TIER.PLATINUM })),
        expectedHumans: 4,
        expectedTier: TIER.PLATINUM,
        minimumDifficulty: 4,
        maximumDifficulty: 5,
        expectedHumanWeight: 1,
      },
    ];

    for (const [index, scenario] of scenarios.entries()) {
      if (index > 0) {
        await testEnv.clearDatabase();
        await adminRequest("", "DELETE");
      }
      await assertFullScenario(scenario);
    }
  });

  it("enforces the strict Platinum gate, Rating demotion, privacy and server-only writes", async () => {
    const platinum = (matches, wins) => ({
      rating: 1_800,
      tier: TIER.PLATINUM,
      platinumSeasonMatches: matches,
      platinumSeasonWins: wins,
    });
    const supporting = Array.from({ length: 3 }, () => ({
      rating: 1_800,
      tier: TIER.PLATINUM,
    }));

    const exactHalf = await forceSettlement([platinum(1, 0), ...supporting], [1, 2, 3, 4]);
    const firstUID = exactHalf.context.clients[0].uid;
    assert.equal(exactHalf.settlement.playerResults[firstUID].platinumSeasonMatches, 2);
    assert.equal(exactHalf.settlement.playerResults[firstUID].platinumSeasonWins, 1);
    assert.equal(exactHalf.settlement.playerResults[firstUID].currentTier, TIER.PLATINUM);

    await testEnv.clearDatabase();
    await adminRequest("", "DELETE");
    const promoted = await forceSettlement([platinum(2, 1), ...supporting], [1, 2, 3, 4]);
    const promotedUID = promoted.context.clients[0].uid;
    assert.equal(promoted.settlement.playerResults[promotedUID].platinumSeasonMatches, 3);
    assert.equal(promoted.settlement.playerResults[promotedUID].platinumSeasonWins, 2);
    assert.equal(promoted.settlement.playerResults[promotedUID].currentTier, TIER.RATING_BATTLE);

    await assertFails(set(ref(
      promoted.context.clients[0].database,
      `competitiveV2/matchmaking/private/profiles/${promotedUID}/competitive/hiddenRating`
    ), 9_999));
    await assertFails(set(ref(
      promoted.context.clients[0].database,
      `competitiveV2/matches/${promoted.context.matchId}/private/config/questionSelection/difficultyBand`
    ), { minimum: 1, maximum: 1 }));
    const publicProfile = await projection(promoted.context.clients[0]);
    assert.equal(publicProfile.competitive.displayRating, 1_820);
    assert.equal(JSON.stringify(publicProfile).includes("platinumSeasonMatches"), false);
    assert.equal(JSON.stringify(publicProfile).includes("hiddenRating"), false);

    await testEnv.clearDatabase();
    await adminRequest("", "DELETE");
    const ratingBattlePlayer = {
      rating: RATING_CONFIG.ratingBattleThreshold,
      tier: TIER.RATING_BATTLE,
      platinumSeasonMatches: 3,
      platinumSeasonWins: 2,
    };
    const demoted = await forceSettlement(
      [ratingBattlePlayer, ...Array.from({ length: 3 }, () => ({
        rating: 1_800,
        tier: TIER.RATING_BATTLE,
        platinumSeasonMatches: 3,
        platinumSeasonWins: 2,
      }))],
      [4, 1, 2, 3]
    );
    const demotedUID = demoted.context.clients[0].uid;
    assert.equal(demoted.settlement.playerResults[demotedUID].mmrAfter, 1_780);
    assert.equal(demoted.settlement.playerResults[demotedUID].currentTier, TIER.PLATINUM);
  });
});
