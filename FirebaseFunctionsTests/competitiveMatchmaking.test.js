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

async function createClient(authenticated = true) {
  const app = initializeApp({
    apiKey: "demo-key",
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
    databaseURL: `https://${projectId}.firebaseio.com`,
  }, `phase-b-${randomUUID()}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  let uid = null;
  if (authenticated) uid = (await signInAnonymously(auth)).user.uid;
  const functions = getFunctions(app, region);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const database = getDatabase(app);
  connectDatabaseEmulator(database, "127.0.0.1", 9100);
  return { app, auth, uid, functions, database };
}

function joinIntent(intentId = `join-${randomUUID()}`, overrides = {}) {
  return {
    intentId,
    type: "joinQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-b-emulator",
    payload: {},
    ...overrides,
  };
}

function cancelIntent(session, intentId = `cancel-${randomUUID()}`, overrides = {}) {
  return {
    intentId,
    type: "cancelQueue",
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-b-emulator",
    sessionId: session.sessionId,
    sessionEpoch: session.sessionEpoch,
    payload: {},
    ...overrides,
  };
}

async function matchmaking(client, event) {
  return (await httpsCallable(client.functions, "competitiveMatchmaking")(event)).data;
}

async function waitFor(predicate, description, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function projection(client) {
  return (await get(ref(
    client.database,
    `competitiveV2/matchmaking/public/${client.uid}`
  ))).val();
}

async function waitForProjection(client, expectedState) {
  return waitFor(async () => {
    const value = await projection(client);
    return value?.state === expectedState ? value : null;
  }, `${client.uid} projection ${expectedState}`);
}

async function queueClients(count) {
  const clients = await Promise.all(Array.from({ length: count }, () => createClient()));
  const acks = await Promise.all(clients.map((client) => matchmaking(client, joinIntent())));
  assert.ok(acks.every((ack) => ["ACCEPTED", "DUPLICATE"].includes(ack.status)));
  const projections = await Promise.all(clients.map((client) =>
    waitForProjection(client, "WAITING_PLAYERS")
  ));
  return { clients, acks, projections };
}

describe("Competitive Phase B Emulator", () => {
  it("matches 4 humans once and connects the assignment to Phase A-2 joinMatch", async () => {
    const { clients, projections } = await queueClients(4);
    const matchIds = new Set(projections.map((value) => value.matchId));
    assert.equal(matchIds.size, 1);
    const matchId = projections[0].matchId;
    const match = await adminRequest(`competitiveV2/matches/${matchId}`);
    assert.equal(match.private.phase, PHASE.WAITING_PLAYERS);
    assert.equal(Object.keys(match.private.participants).length, 4);

    for (const [index, client] of clients.entries()) {
      const projectionValue = projections[index];
      const ack = (await httpsCallable(client.functions, "competitiveIntent")({
        intentId: `join-match-${randomUUID()}`,
        type: "joinMatch",
        protocolVersion: PROTOCOL_VERSION,
        clientBuild: "phase-b-emulator",
        sessionId: projectionValue.sessionId,
        sessionEpoch: projectionValue.sessionEpoch,
        matchId,
        lastSeenServerSequence: 0,
        payload: { assignmentTicket: projectionValue.assignmentTicket },
      })).data;
      assert.equal(ack.status, "ACCEPTED");
    }

    const finishedPrivate = await adminRequest(`competitiveV2/matches/${matchId}/private`);
    finishedPrivate.phase = PHASE.MATCH_FINISHED;
    finishedPrivate.matchResult = {
      matchId,
      outcome: "COMPLETED",
      finalScores: {},
      ranks: {},
      winnerUIDs: [],
      forfeitedUIDs: [],
      finishedAtEpochMs: Date.now(),
      configVersion: finishedPrivate.configVersion,
    };
    await adminRequest(`competitiveV2/matches/${matchId}/private`, "PUT", finishedPrivate);
    const firstSession = projections[0];
    const reconcile = (await httpsCallable(clients[0].functions, "competitiveReconcileMatch")({
      intentId: `finish-${randomUUID()}`,
      type: "reconcile",
      protocolVersion: PROTOCOL_VERSION,
      clientBuild: "phase-b-emulator",
      sessionId: firstSession.sessionId,
      sessionEpoch: firstSession.sessionEpoch,
      matchId,
      lastSeenServerSequence: 0,
      payload: {},
    })).data;
    assert.equal(reconcile.status, "ACCEPTED");
    await Promise.all(clients.map((client) => waitForProjection(client, "NOT_QUEUED")));
  });

  it("serializes concurrent matchmakers so 8 humans become 2 disjoint matches", async () => {
    const { clients, projections } = await queueClients(8);
    const matchIds = new Set(projections.map((value) => value.matchId));
    assert.equal(matchIds.size, 2);
    const matches = await adminRequest("competitiveV2/matches");
    assert.equal(Object.keys(matches).length, 2);
    const assigned = Object.values(matches).flatMap((match) =>
      Object.keys(match.private.participants)
    );
    assert.equal(assigned.length, 8);
    assert.equal(new Set(assigned).size, 8);
    assert.deepEqual(new Set(assigned), new Set(clients.map((client) => client.uid)));
    assert.equal(await adminRequest("competitiveV2/matchmaking/private/pendingMatches"), null);
  });

  it("keeps join/cancel retry-safe and rejects stale sessions", async () => {
    const client = await createClient();
    const stableJoin = joinIntent("stable-join");
    const first = await matchmaking(client, stableJoin);
    const duplicate = await matchmaking(client, stableJoin);
    assert.equal(first.status, "ACCEPTED");
    assert.equal(duplicate.status, "DUPLICATE");
    assert.equal(duplicate.sessionEpoch, first.sessionEpoch);

    const replacement = await matchmaking(client, joinIntent("replacement-session"));
    assert.equal(replacement.sessionEpoch, first.sessionEpoch + 1);
    const stale = await matchmaking(client, cancelIntent(first, "stale-cancel"));
    assert.equal(stale.rejectionCode, "STALE_SESSION_EPOCH");

    const stableCancel = cancelIntent(replacement, "stable-cancel");
    assert.equal((await matchmaking(client, stableCancel)).status, "ACCEPTED");
    assert.equal((await matchmaking(client, stableCancel)).status, "DUPLICATE");
    assert.equal((await waitForProjection(client, "NOT_QUEUED")).state, "NOT_QUEUED");
  });

  it("enforces Security Gate B at callable and Rules boundaries", async () => {
    const unauthenticated = await createClient(false);
    await assert.rejects(
      matchmaking(unauthenticated, joinIntent()),
      (error) => error.code === "functions/unauthenticated"
    );

    const owner = await createClient();
    const other = await createClient();
    assert.equal((await matchmaking(owner, joinIntent())).status, "ACCEPTED");
    assert.equal((await matchmaking(owner, joinIntent(`bad-${randomUUID()}`, {
      payload: { mmr: 9_999 },
    }))).rejectionCode, "INVALID_PAYLOAD");
    assert.equal((await matchmaking(owner, joinIntent(`old-${randomUUID()}`, {
      protocolVersion: "competitive-v1",
    }))).rejectionCode, "PROTOCOL_UNSUPPORTED");
    assert.equal((await matchmaking(owner, {
      ...joinIntent(`uid-${randomUUID()}`),
      uid: other.uid,
    })).rejectionCode, "INVALID_PAYLOAD");

    await assertSucceeds(get(ref(
      owner.database,
      `competitiveV2/matchmaking/public/${owner.uid}`
    )));
    await assertFails(get(ref(
      other.database,
      `competitiveV2/matchmaking/public/${owner.uid}`
    )));
    await assertFails(get(ref(owner.database, "competitiveV2/matchmaking/private/queue")));
    await assertFails(set(ref(
      owner.database,
      `competitiveV2/matches/chosen/private/participants/${owner.uid}`
    ), { uid: owner.uid }));
  });

  it("rejects stale cancellation and a second queue after MATCH_FOUND", async () => {
    const { clients, projections } = await queueClients(4);
    const owner = clients[0];
    const session = projections[0];
    const cancel = await matchmaking(owner, cancelIntent(session, "late-cancel"));
    assert.equal(cancel.rejectionCode, "MATCH_ALREADY_ASSIGNED");
    const secondQueue = await matchmaking(owner, joinIntent("second-active-match"));
    assert.equal(secondQueue.rejectionCode, "ACTIVE_MATCH_EXISTS");
    const matches = await adminRequest("competitiveV2/matches");
    assert.equal(Object.keys(matches).length, 1);
  });
});
