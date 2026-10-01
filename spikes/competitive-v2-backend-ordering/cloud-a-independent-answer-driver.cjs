#!/usr/bin/env node

"use strict";

const { performance } = require("node:perf_hooks");

const PLAYERS = ["A", "B", "C", "D"];
const CORRECT_ANSWER_ID = "answer-correct";

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function positiveInteger(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined) return fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function safeId(value, name) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(value)) {
    throw new Error(`${name} must use the Spike safe identifier format`);
  }
  return value;
}

function endpoint(value, name) {
  const url = new URL(value);
  if (url.protocol !== "https:") throw new Error(`${name} must use HTTPS`);
  return url.toString();
}

function configuration() {
  return {
    controlUrl: endpoint(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_CONTROL_URL"),
      "COMPETITIVE_V2_SPIKE_CONTROL_URL"
    ),
    orderUrl: endpoint(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_ORDER_URL"),
      "COMPETITIVE_V2_SPIKE_ORDER_URL"
    ),
    token: requiredEnvironment("COMPETITIVE_V2_SPIKE_TOKEN"),
    runId: safeId(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_RUN_ID"),
      "COMPETITIVE_V2_SPIKE_RUN_ID"
    ),
    testOrigin: requiredEnvironment("COMPETITIVE_V2_SPIKE_TEST_ORIGIN"),
    warmupRounds: positiveInteger("COMPETITIVE_V2_SPIKE_WARMUP_ROUNDS", 10),
    measuredRounds: positiveInteger("COMPETITIVE_V2_SPIKE_MEASURED_ROUNDS", 40),
    raceRounds: positiveInteger("COMPETITIVE_V2_SPIKE_RACE_ROUNDS", 12),
    keepData: process.env.COMPETITIVE_V2_SPIKE_KEEP_DATA === "1",
    cleanupOnly: process.env.COMPETITIVE_V2_SPIKE_CLEANUP_ONLY === "1",
  };
}

async function postJson(url, token, body, playerId = null) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-competitive-spike-token": token,
      ...(playerId ? { "x-competitive-spike-player-id": playerId } : {}),
    },
    body: JSON.stringify(body),
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error(`HTTP ${response.status} returned non-JSON response`);
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}

function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION_FAILED: ${message}`);
}

function answerIntent(config, matchId, playerId, eventId, answerId) {
  return {
    runId: config.runId,
    matchId,
    questionId: "spike-question-1",
    answerId,
    eventId,
    sessionId: `session-${playerId}`,
    sessionEpoch: 1,
  };
}

async function control(config, action, matchId = null, extra = {}) {
  return postJson(config.controlUrl, config.token, {
    action,
    runId: config.runId,
    ...(matchId ? { matchId } : {}),
    ...extra,
  });
}

async function initialize(config, matchId, durationMs = 60_000) {
  return control(config, "initialize", matchId, { durationMs });
}

async function status(config, matchId) {
  return control(config, "status", matchId);
}

async function closeQuestion(config, matchId, reason, closeEventId) {
  return control(config, "close", matchId, {
    questionId: "spike-question-1",
    reason,
    closeEventId,
  });
}

async function sendAnswer(config, matchId, playerId, eventId, answerId) {
  const t0MonotonicMs = performance.now();
  const result = await postJson(
    config.orderUrl,
    config.token,
    answerIntent(config, matchId, playerId, eventId, answerId),
    playerId
  );
  result.driverTiming = { t0ToT3Ms: performance.now() - t0MonotonicMs };
  return result;
}

function nearestRank(values, ratio) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * ratio) - 1)];
}

function roundMetric(value) {
  return Number(value.toFixed(3));
}

function metricSummary(results, selector) {
  const values = results.map(selector).filter(Number.isFinite);
  return {
    count: values.length,
    min: roundMetric(Math.min(...values)),
    p50: roundMetric(nearestRank(values, 0.50)),
    p95: roundMetric(nearestRank(values, 0.95)),
    max: roundMetric(Math.max(...values)),
  };
}

function latencySummary(results) {
  return {
    t1ToT2Ms: metricSummary(results, (result) => result.timing.t1ToT2Ms),
    t0ToT3Ms: metricSummary(results, (result) => result.driverTiming.t0ToT3Ms),
    accessTokenMs: metricSummary(results, (result) => result.timing.accessTokenMs),
    rtdbMs: metricSummary(results, (result) => result.timing.rtdbMs),
  };
}

function aggregateOperations(results) {
  return results.reduce(
    (totals, result) => {
      for (const key of Object.keys(totals)) {
        totals[key] += result.operations?.[key] || 0;
      }
      return totals;
    },
    { reads: 0, writeAttempts: 0, successfulWrites: 0, contentionRetries: 0 }
  );
}

function runtimeSummary(results) {
  const instances = new Map();
  for (const result of results) {
    const id = result.runtime.instanceId;
    const entry = instances.get(id) || { requests: 0, coldInstanceInvocations: 0 };
    entry.requests += 1;
    if (result.runtime.coldInstanceInvocation) entry.coldInstanceInvocations += 1;
    instances.set(id, entry);
  }
  return {
    instanceCount: instances.size,
    instances: [...instances.entries()].map(([instanceId, value]) => ({
      instanceId,
      ...value,
    })),
  };
}

function assertFourAnswerResult(results, closeResult, matchId) {
  assert(results.length === 4, `${matchId}: four responses required`);
  assert(results.every((value) => value.status === "accepted" && value.accepted),
    `${matchId}: all four answers must be independently accepted`);
  assert(new Set(closeResult.result.answerOrder).size === 4,
    `${matchId}: canonical answer order must contain four unique players`);
  assert(closeResult.result.wrongPlayerIds.includes("B")
      && closeResult.result.wrongPlayerIds.includes("D"),
  `${matchId}: B/D must be wrong`);
  assert(new Set(closeResult.result.correctPlayerIds).size === 2
      && closeResult.result.correctPlayerIds.includes("A")
      && closeResult.result.correctPlayerIds.includes("C"),
  `${matchId}: A/C must be the two correct players`);
  assert(
    [closeResult.result.scoreDeltas.A, closeResult.result.scoreDeltas.C]
      .sort((left, right) => right - left)
      .join(",") === "20,10",
    `${matchId}: correct players must receive 20/10 by canonical order`
  );
  assert(closeResult.result.scoreDeltas.B === -10
      && closeResult.result.scoreDeltas.D === -10,
  `${matchId}: wrong answers must receive -10`);
}

async function concurrentRound(config, matchId) {
  await initialize(config, matchId);
  const results = await Promise.all(
    PLAYERS.map((playerId, index) => sendAnswer(
      config,
      matchId,
      playerId,
      `${matchId}-${playerId}`,
      index % 2 === 0 ? CORRECT_ANSWER_ID : `answer-wrong-${(index % 3) + 1}`
    ))
  );
  const closed = await closeQuestion(
    config,
    matchId,
    "ALL_ANSWERED",
    `close-${matchId}`
  );
  assert(closed.status === "accepted", `${matchId}: all-answered close must succeed`);
  assertFourAnswerResult(results, closed, matchId);
  const persisted = await status(config, matchId);
  assert(persisted.state.phase === "QUESTION_RESULT", `${matchId}: result phase required`);
  assert(Object.keys(persisted.state.answers || {}).length === 4,
    `${matchId}: exactly four answer records required`);
  assert(JSON.stringify(persisted.state.result.scoreDeltas)
      === JSON.stringify(closed.result.scoreDeltas),
  `${matchId}: persisted score must match close result`);
  return { results, close: closed };
}

async function runMeasured(config) {
  for (let index = 0; index < config.warmupRounds; index += 1) {
    await concurrentRound(config, `warmup-${String(index + 1).padStart(3, "0")}`);
  }
  const answers = [];
  const closes = [];
  for (let index = 0; index < config.measuredRounds; index += 1) {
    const outcome = await concurrentRound(
      config,
      `measured-${String(index + 1).padStart(3, "0")}`
    );
    answers.push(...outcome.results);
    closes.push(outcome.close);
  }
  return {
    answers,
    closes,
    latency: latencySummary(answers),
    answerOperations: aggregateOperations(answers),
    closeOperations: aggregateOperations(closes),
    runtime: runtimeSummary(answers),
  };
}

async function runSafety(config) {
  const matchId = "safety-duplicate";
  await initialize(config, matchId);
  const originalIntent = answerIntent(
    config,
    matchId,
    "A",
    "duplicate-event-A",
    CORRECT_ANSWER_ID
  );
  const original = await postJson(config.orderUrl, config.token, originalIntent, "A");
  const retry = await postJson(config.orderUrl, config.token, originalIntent, "A");
  const second = await sendAnswer(
    config,
    matchId,
    "A",
    "second-event-A",
    CORRECT_ANSWER_ID
  );
  assert(original.status === "accepted", "original answer must be accepted");
  assert(retry.status === "duplicate" && retry.accepted,
    "same event retry must return accepted duplicate");
  assert(second.code === "DUPLICATE_ANSWER", "second answer must be rejected");

  const retryMatch = "safety-concurrent-retry";
  await initialize(config, retryMatch);
  const retryBody = answerIntent(
    config,
    retryMatch,
    "B",
    "concurrent-retry-B",
    CORRECT_ANSWER_ID
  );
  const concurrent = await Promise.all([
    postJson(config.orderUrl, config.token, retryBody, "B"),
    postJson(config.orderUrl, config.token, retryBody, "B"),
  ]);
  assert(concurrent.filter((value) => value.status === "accepted").length === 1,
    "concurrent retry must accept once");
  assert(concurrent.filter((value) => value.status === "duplicate").length === 1,
    "concurrent retry must return one duplicate");
  const retryStatus = await status(config, retryMatch);
  assert(Object.keys(retryStatus.state.answers || {}).length === 1,
    "concurrent retry must persist one answer");

  const validationMatch = "safety-validation";
  await initialize(config, validationMatch);
  const staleQuestionBody = answerIntent(
    config,
    validationMatch,
    "C",
    "stale-question-C",
    CORRECT_ANSWER_ID
  );
  staleQuestionBody.questionId = "old-question";
  const staleQuestion = await postJson(
    config.orderUrl,
    config.token,
    staleQuestionBody,
    "C"
  );
  const wrongSessionBody = answerIntent(
    config,
    validationMatch,
    "C",
    "wrong-session-C",
    CORRECT_ANSWER_ID
  );
  wrongSessionBody.sessionId = "session-D";
  const wrongSession = await postJson(
    config.orderUrl,
    config.token,
    wrongSessionBody,
    "C"
  );
  const malformedBody = answerIntent(
    config,
    validationMatch,
    "C",
    "malformed-C",
    CORRECT_ANSWER_ID
  );
  malformedBody.correct = true;
  malformedBody.scoreDelta = 999;
  const malformed = await postJson(
    config.orderUrl,
    config.token,
    malformedBody,
    "C"
  );
  const otherPlayerBody = answerIntent(
    config,
    validationMatch,
    "C",
    "other-player-C",
    CORRECT_ANSWER_ID
  );
  otherPlayerBody.playerId = "D";
  const otherPlayer = await postJson(
    config.orderUrl,
    config.token,
    otherPlayerBody,
    "C"
  );
  assert(staleQuestion.code === "STALE_QUESTION", "stale question must be rejected");
  assert(wrongSession.code === "STALE_SESSION", "wrong session must be rejected");
  assert(malformed.code === "MALFORMED_REQUEST", "result fields must be rejected");
  assert(otherPlayer.code === "MALFORMED_REQUEST", "payload player target must be rejected");
  return {
    duplicateEvent: retry.status,
    duplicateAnswer: second.code,
    concurrentRetryStatuses: concurrent.map((value) => value.status),
    concurrentRetryContention: aggregateOperations(concurrent).contentionRetries,
    staleQuestion: staleQuestion.code,
    wrongSession: wrongSession.code,
    forgedResultFields: malformed.code,
    otherPlayerTarget: otherPlayer.code,
  };
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitUntil(epochMs) {
  const remaining = epochMs - Date.now();
  if (remaining > 0) await sleep(remaining);
}

async function closeAfterDeadline(config, matchId, closeEventPrefix) {
  let result = await closeQuestion(
    config,
    matchId,
    "DEADLINE",
    `${closeEventPrefix}-1`
  );
  if (result.code === "DEADLINE_NOT_REACHED") {
    await sleep(150);
    result = await closeQuestion(
      config,
      matchId,
      "DEADLINE",
      `${closeEventPrefix}-2`
    );
  }
  assert(result.status === "accepted" || result.status === "duplicate",
    `${matchId}: deadline close must converge`);
  return result;
}

async function runDeadline(config) {
  const beforeMatch = "deadline-clear-before";
  await initialize(config, beforeMatch, 2_000);
  const beforeStatus = await status(config, beforeMatch);
  const before = await sendAnswer(
    config,
    beforeMatch,
    "A",
    "clear-before-A",
    CORRECT_ANSWER_ID
  );
  await waitUntil(beforeStatus.state.questionDeadlineEpochMs + 150);
  const beforeClose = await closeAfterDeadline(config, beforeMatch, "close-before");
  assert(before.accepted && beforeClose.result.answerEventIds.A === "clear-before-A",
    "clear-before answer must be accepted and included");

  const afterMatch = "deadline-clear-after";
  await initialize(config, afterMatch, 500);
  const afterStatus = await status(config, afterMatch);
  await waitUntil(afterStatus.state.questionDeadlineEpochMs + 200);
  const after = await sendAnswer(
    config,
    afterMatch,
    "A",
    "clear-after-A",
    CORRECT_ANSWER_ID
  );
  const afterClose = await closeAfterDeadline(config, afterMatch, "close-after");
  assert(!after.accepted && after.code === "DEADLINE_EXCEEDED",
    "clear-after answer must be rejected by RTDB timestamp");
  assert(!afterClose.result.answerEventIds?.A,
    "clear-after answer must be excluded from result");

  let raceAccepted = 0;
  let raceRejected = 0;
  let closeContentionRetries = 0;
  const raceInstances = new Set();
  for (let index = 0; index < config.raceRounds; index += 1) {
    const matchId = `deadline-race-${String(index + 1).padStart(3, "0")}`;
    await initialize(config, matchId, 1_200);
    const current = await status(config, matchId);
    const deadline = current.state.questionDeadlineEpochMs;
    const answerPromise = (async () => {
      await waitUntil(deadline - 120);
      return sendAnswer(
        config,
        matchId,
        "A",
        `race-answer-${index}`,
        CORRECT_ANSWER_ID
      );
    })();
    const closePromise = (async () => {
      await waitUntil(deadline + 5);
      return closeAfterDeadline(config, matchId, `race-close-${index}`);
    })();
    const [answer, closed] = await Promise.all([answerPromise, closePromise]);
    raceInstances.add(answer.runtime.instanceId);
    closeContentionRetries += closed.operations.contentionRetries;
    const included = closed.result.answerEventIds?.A === `race-answer-${index}`;
    if (answer.accepted) {
      raceAccepted += 1;
      assert(included, `${matchId}: accepted ack must be included`);
    } else {
      raceRejected += 1;
      assert(!included, `${matchId}: rejected ack must be excluded`);
    }
    const resultBeforeLate = JSON.stringify((await status(config, matchId)).state.result);
    const late = await sendAnswer(
      config,
      matchId,
      "B",
      `late-answer-${index}`,
      CORRECT_ANSWER_ID
    );
    assert(!late.accepted, `${matchId}: result-phase answer must be rejected`);
    const resultAfterLate = JSON.stringify((await status(config, matchId)).state.result);
    assert(resultAfterLate === resultBeforeLate, `${matchId}: result must be immutable`);
  }
  return {
    authority: "RTDB Server timestamp for answer and close; client and Function clocks excluded",
    clearBefore: { status: before.status, included: true },
    clearAfter: { status: after.status, code: after.code, included: false },
    raceRounds: config.raceRounds,
    raceAccepted,
    raceRejected,
    closeContentionRetries,
    answerInstanceCount: raceInstances.size,
    resultMutationAfterLateAnswer: 0,
  };
}

async function runRepresentativeScore(config) {
  const matchId = "score-representative";
  await initialize(config, matchId, 3_000);
  const opened = await status(config, matchId);
  const a = await sendAnswer(
    config,
    matchId,
    "A",
    "score-A",
    CORRECT_ANSWER_ID
  );
  await sleep(150);
  const b = await sendAnswer(
    config,
    matchId,
    "B",
    "score-B",
    "answer-wrong-1"
  );
  await sleep(150);
  const c = await sendAnswer(
    config,
    matchId,
    "C",
    "score-C",
    CORRECT_ANSWER_ID
  );
  assert(a.accepted && b.accepted && c.accepted, "representative answers must be accepted");
  await waitUntil(opened.state.questionDeadlineEpochMs + 150);
  const closed = await closeAfterDeadline(config, matchId, "score-close");
  assert(JSON.stringify(closed.result.scoreDeltas)
      === JSON.stringify({ A: 20, B: -10, C: 10, D: 0 }),
  "representative score must match Product rule");
  return {
    answerOrder: closed.result.answerOrder,
    correctPlayerIds: closed.result.correctPlayerIds,
    wrongPlayerIds: closed.result.wrongPlayerIds,
    unansweredPlayerIds: closed.result.unansweredPlayerIds,
    scoreDeltas: closed.result.scoreDeltas,
  };
}

async function runTie(config) {
  const matchId = "canonical-tie";
  await control(config, "initializeTie", matchId);
  const closed = await closeQuestion(
    config,
    matchId,
    "ALL_ANSWERED",
    "tie-close"
  );
  assert(closed.result.answerOrder.join(",") === PLAYERS.join(","),
    "exact RTDB timestamp tie must use participant order");
  assert(JSON.stringify(closed.result.scoreDeltas)
      === JSON.stringify({ A: 20, B: 10, C: 5, D: 1 }),
  "tie score must follow participant order");
  return {
    answerOrder: closed.result.answerOrder,
    scoreDeltas: closed.result.scoreDeltas,
  };
}

async function run(config) {
  if (config.cleanupOnly) return control(config, "cleanup");
  const cleanup = { attempted: false, status: "kept" };
  try {
    const measured = await runMeasured(config);
    const safety = await runSafety(config);
    const deadline = await runDeadline(config);
    const representativeScore = await runRepresentativeScore(config);
    const tie = await runTie(config);
    const warmAnswers = measured.answers.filter(
      (answer) => !answer.runtime.coldInstanceInvocation
    );
    return {
      status: "complete",
      candidate: "A-functions-2nd-gen-rtdb-independent-close-order",
      environment: {
        testOrigin: config.testOrigin,
        functionRegion: measured.answers[0].runtime.region,
        rtdbHost: measured.answers[0].runtime.rtdbHost,
        runId: config.runId,
        warmupRounds: config.warmupRounds,
        measuredRounds: config.measuredRounds,
        concurrentAnswersPerRound: PLAYERS.length,
        spikeOrderConcurrency: 1,
        spikeMaxInstances: 4,
      },
      measured: {
        answerIntentCount: measured.answers.length,
        acceptedAnswerCount: measured.answers.filter((answer) => answer.accepted).length,
        coldInstanceAnswerCount: measured.answers.length - warmAnswers.length,
        latencyAll: measured.latency,
        latencyWarm: latencySummary(warmAnswers),
        answerOperations: measured.answerOperations,
        closeOperations: measured.closeOperations,
        runtime: measured.runtime,
      },
      safety,
      deadline,
      canonicalOrdering: {
        authority: "RTDB Server timestamp ascending; exact tie uses participant order",
        clientTimestampUsed: false,
        functionClockUsedForAuthority: false,
        exactTie: tie,
      },
      representativeScore,
      normalPathOperationsPerQuestion: {
        functionInvocations: 5,
        rtdbReads: measured.answerOperations.reads / config.measuredRounds
          + measured.closeOperations.reads / config.measuredRounds,
        rtdbWriteAttempts: measured.answerOperations.writeAttempts / config.measuredRounds
          + measured.closeOperations.writeAttempts / config.measuredRounds,
        contentionRetries: measured.answerOperations.contentionRetries
          / config.measuredRounds
          + measured.closeOperations.contentionRetries / config.measuredRounds,
      },
      cleanup,
    };
  } finally {
    if (!config.keepData) {
      cleanup.attempted = true;
      cleanup.status = "pending";
      try {
        const result = await control(config, "cleanup");
        cleanup.status = result.status;
      } catch (error) {
        cleanup.status = "failed";
        cleanup.error = error.message;
      }
    }
  }
}

async function main() {
  const config = configuration();
  const result = await run(config);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { run };
