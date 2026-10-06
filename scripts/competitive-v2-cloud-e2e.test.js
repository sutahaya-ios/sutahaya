"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DATABASE_HOST,
  EXECUTION_CONFIRMATION,
  PROJECT_ID,
  executionConfiguration,
  latencySummary,
  makeMatchId,
  parseTestUIDs,
  questionStrategy,
  reviewPlan,
} = require("./competitive-v2-cloud-e2e.cjs");

function validEnvironment() {
  return {
    COMPETITIVE_V2_E2E_ALLOW_PRODUCTION: EXECUTION_CONFIRMATION,
    COMPETITIVE_V2_E2E_PROJECT_ID: PROJECT_ID,
    COMPETITIVE_V2_E2E_DATABASE_URL: `https://${DATABASE_HOST}`,
    COMPETITIVE_V2_E2E_AUTH_DOMAIN: `${PROJECT_ID}.firebaseapp.com`,
    COMPETITIVE_V2_E2E_API_KEY: "runtime-only-placeholder",
    COMPETITIVE_V2_E2E_TEST_UIDS: "test-a,test-b,test-c,test-d",
  };
}

test("review mode identifies only the isolated Phase A-2 resources", () => {
  const plan = reviewPlan();
  assert.equal(plan.productionWritePerformed, false);
  assert.deepEqual(plan.functions, [
    "competitiveIntent",
    "competitiveReconcileMatch",
  ]);
  assert.match(plan.namespace, /^competitiveV2\/matches\//);
  assert.doesNotMatch(JSON.stringify(plan), /sendRoomInvite|OrderingSpike/);
});

test("production execution requires the exact explicit confirmation", () => {
  const environment = validEnvironment();
  delete environment.COMPETITIVE_V2_E2E_ALLOW_PRODUCTION;
  assert.throws(() => executionConfiguration(environment), /confirmation is missing/);
});

test("production execution refuses another project or database", () => {
  assert.throws(() => executionConfiguration({
    ...validEnvironment(),
    COMPETITIVE_V2_E2E_PROJECT_ID: "another-project",
  }), /Project must be/);
  assert.throws(() => executionConfiguration({
    ...validEnvironment(),
    COMPETITIVE_V2_E2E_DATABASE_URL: "https://example.invalid",
  }), /Database must be/);
});

test("production execution accepts exactly four unique runtime UIDs", () => {
  const config = executionConfiguration(validEnvironment());
  assert.equal(config.testUIDs.length, 4);
  assert.equal(config.projectId, PROJECT_ID);
  assert.throws(() => parseTestUIDs("a,b,c"), /exactly four/);
  assert.throws(() => parseTestUIDs("a,b,c,c"), /four unique/);
});

test("question strategies cover scoring, deadline, and security cases", () => {
  assert.equal(questionStrategy(0), "ALL_CORRECT_ORDERED");
  assert.equal(questionStrategy(1), "WRONG_THEN_CORRECT");
  assert.equal(questionStrategy(2), "DEADLINE_WITH_UNANSWERED");
  assert.equal(questionStrategy(3), "SECURITY_AND_IDEMPOTENCY");
  assert.equal(questionStrategy(19), "ALL_CORRECT_ORDERED");
});

test("latency summary keeps min, p50, p95, and max for T0 through T4", () => {
  const metrics = Array.from({ length: 20 }, (_, index) => ({
    t1ToT2Ms: index + 1,
    t0ToT3Ms: (index + 1) * 2,
    t0ToT4Ms: (index + 1) * 3,
  }));
  assert.deepEqual(latencySummary(metrics), {
    t1ToT2Ms: { count: 20, min: 1, p50: 10, p95: 19, max: 20 },
    t0ToT3Ms: { count: 20, min: 2, p50: 20, p95: 38, max: 40 },
    t0ToT4Ms: { count: 20, min: 3, p50: 30, p95: 57, max: 60 },
  });
});

test("generated match IDs stay inside the isolated E2E namespace", () => {
  assert.match(makeMatchId(), /^e2e-a2-\d+-[0-9a-f-]{36}$/);
});
