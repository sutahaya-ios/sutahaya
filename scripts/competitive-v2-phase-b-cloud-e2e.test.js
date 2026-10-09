"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DATABASE_HOST,
  EXECUTION_CONFIRMATION,
  PROJECT_ID,
  TEST_UID_ENV_NAMES,
  assignmentMeasurement,
  cleanupTargets,
  executionConfiguration,
  isAbsentRTDBField,
  isAssignmentProjection,
  makeRunId,
  makeSentinelId,
  matchmakingIntent,
  parseTestUIDs,
  reviewPlan,
  safeErrorMessage,
} = require("./competitive-v2-phase-b-cloud-e2e.cjs");

function validEnvironment() {
  return {
    COMPETITIVE_V2_PHASE_B_E2E_ALLOW_PRODUCTION: EXECUTION_CONFIRMATION,
    COMPETITIVE_V2_PHASE_B_E2E_PROJECT_ID: PROJECT_ID,
    COMPETITIVE_V2_PHASE_B_E2E_DATABASE_URL: "https://" + DATABASE_HOST,
    COMPETITIVE_V2_PHASE_B_E2E_AUTH_DOMAIN: PROJECT_ID + ".firebaseapp.com",
    COMPETITIVE_V2_PHASE_B_E2E_API_KEY: "runtime-only-placeholder",
    COMPETITIVE_TEST_UID_1: "test-a",
    COMPETITIVE_TEST_UID_2: "test-b",
    COMPETITIVE_TEST_UID_3: "test-c",
    COMPETITIVE_TEST_UID_4: "test-d",
  };
}

test("review mode is read-only and identifies only Phase B resources", () => {
  const plan = reviewPlan();
  assert.equal(plan.productionReadPerformed, false);
  assert.equal(plan.productionWritePerformed, false);
  assert.deepEqual(plan.functions, [
    "competitiveMatchmaking",
    "competitiveIntent",
    "competitiveReconcileMatch",
  ]);
  assert.equal(plan.userCount, 4);
  assert.doesNotMatch(JSON.stringify(plan), /sendRoomInvite|rooms\//);
});

test("execution requires the exact Production confirmation", () => {
  const environment = validEnvironment();
  delete environment.COMPETITIVE_V2_PHASE_B_E2E_ALLOW_PRODUCTION;
  assert.throws(() => executionConfiguration(environment), /confirmation is missing/);
});

test("execution refuses another project, database, or auth domain", () => {
  assert.throws(() => executionConfiguration({
    ...validEnvironment(),
    COMPETITIVE_V2_PHASE_B_E2E_PROJECT_ID: "another-project",
  }), /Project must be/);
  assert.throws(() => executionConfiguration({
    ...validEnvironment(),
    COMPETITIVE_V2_PHASE_B_E2E_DATABASE_URL: "https://example.invalid",
  }), /Database must be/);
  assert.throws(() => executionConfiguration({
    ...validEnvironment(),
    COMPETITIVE_V2_PHASE_B_E2E_AUTH_DOMAIN: "example.invalid",
  }), /Auth domain must be/);
});

test("four existing test UIDs are injected separately and must be unique", () => {
  const environment = validEnvironment();
  assert.deepEqual(parseTestUIDs(environment), [
    "test-a",
    "test-b",
    "test-c",
    "test-d",
  ]);
  const missing = { ...environment };
  delete missing[TEST_UID_ENV_NAMES[3]];
  assert.throws(() => parseTestUIDs(missing), /Missing required environment variable/);
  assert.throws(() => parseTestUIDs({
    ...environment,
    COMPETITIVE_TEST_UID_4: "test-c",
  }), /must be unique/);
});

test("matchmaking intents contain no client authority fields by default", () => {
  const intent = matchmakingIntent("joinQueue", "event-1");
  assert.deepEqual(intent, {
    intentId: "event-1",
    type: "joinQueue",
    protocolVersion: intent.protocolVersion,
    clientBuild: "competitive-v2-phase-b-cloud-e2e",
    payload: {},
  });
  assert.match(intent.protocolVersion, /^competitive-v2-/);
});

test("assignment measurement records T0 to T3 and T4 without inventing T1 or T2", () => {
  const observations = [1, 2, 3, 4].map((offset) => [{
    observedAtMonotonicMs: 100 + offset,
    value: {
      state: "WAITING_PLAYERS",
      matchId: "match-1",
      assignmentTicket: "ticket-" + offset,
    },
  }]);
  const summary = assignmentMeasurement(100, 110, observations, {
    matchId: "match-1",
  });
  assert.deepEqual(summary, {
    t0ToT3Ms: 10,
    t0ToT4Ms: 4,
    t1ToT2Ms: null,
    serverTimingAvailability: "NOT_EXPOSED_BY_CURRENT_FUNCTION",
  });
  assert.equal(isAssignmentProjection(observations[0][0].value, "match-1"), true);
});

test("assignment measurement uses exact server timing only when the ack exposes it", () => {
  const observations = Array.from({ length: 4 }, () => [{
    observedAtMonotonicMs: 105,
    value: {
      state: "MATCH_FOUND",
      matchId: "match-2",
      assignmentTicket: "ticket",
    },
  }]);
  const summary = assignmentMeasurement(100, 106, observations, {
    matchId: "match-2",
    timing: { t1ToT2Ms: 12.3456 },
  });
  assert.equal(summary.t1ToT2Ms, 12.346);
  assert.equal(summary.serverTimingAvailability, "ACK_EXPOSED");
});

test("RTDB release treats null and missing fields as absent, but rejects a value", () => {
  assert.equal(isAbsentRTDBField(null), true);
  assert.equal(isAbsentRTDBField(undefined), true);
  assert.equal(isAbsentRTDBField("match-still-active"), false);
});

test("cleanup plan is exact and rejects broad or excessive targets", () => {
  const runId = makeRunId();
  const sentinelId = makeSentinelId(runId);
  const targets = cleanupTargets({
    testUIDs: ["test-a", "test-b", "test-c", "test-d"],
    sentinelId,
    matchIds: ["match-a", "match-b"],
    pendingMatchIds: ["match-b"],
  });
  assert.equal(targets.length, 18);
  assert(targets.every((target) => target.startsWith("competitiveV2/")));
  assert(targets.every((target) => target !== "competitiveV2"));
  assert(targets.includes("competitiveV2/matches/match-a"));
  assert(targets.includes("competitiveV2/clocks/match-b"));
  assert.throws(() => cleanupTargets({
    testUIDs: ["test-a", "test-b", "test-c", "test-d"],
    sentinelId: "not-run-scoped",
    matchIds: [],
    pendingMatchIds: [],
  }), /run-scoped/);
  assert.throws(() => cleanupTargets({
    testUIDs: ["test-a", "test-b", "test-c", "test-d"],
    sentinelId,
    matchIds: ["a", "b", "c", "d", "e"],
    pendingMatchIds: [],
  }), /exceeds/);
});

test("runtime report errors redact tokens, API keys, and service accounts", () => {
  const jwt = ["eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjMifQ", "signature"].join(".");
  const apiKey = "AI" + "za" + "1".repeat(35);
  const serviceAccount = "firebase-admin" + "@example.iam.gserviceaccount.com";
  const message = safeErrorMessage(
    new Error(jwt + " " + apiKey + " " + serviceAccount)
  );
  assert.doesNotMatch(message, /eyJhbGci/);
  assert.doesNotMatch(message, /AIza/);
  assert.doesNotMatch(message, /firebase-admin@/);
  assert.match(message, /REDACTED_TOKEN/);
  assert.match(message, /REDACTED_API_KEY/);
  assert.match(message, /REDACTED_SERVICE_ACCOUNT/);
});
