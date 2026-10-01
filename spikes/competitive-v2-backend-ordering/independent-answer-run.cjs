#!/usr/bin/env node

/*
 * Competitive v2 Phase A-1 independent-answer local spike.
 *
 * This is disposable test code, not a Production backend. It refuses to run
 * without the RTDB Emulator and only writes below a dedicated spike path.
 */

"use strict";

const assert = require("node:assert/strict");
const http = require("node:http");
const { performance } = require("node:perf_hooks");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-hayaosiapp";
const ROOT_PATH = "competitiveV2Spike/independentAnswers";
const PLAYERS = ["A", "B", "C", "D"];
const CORRECT_ANSWER_ID = "answer-correct";
const VALID_ANSWER_IDS = new Set([
  CORRECT_ANSWER_ID,
  "answer-wrong-1",
  "answer-wrong-2",
  "answer-wrong-3",
]);
const MODEL_GLOBAL = "global-sequence-cas";
const MODEL_INDEPENDENT = "independent-close-order";
const WARMUP_ROUNDS = Number(process.env.SPIKE_WARMUP_ROUNDS || 5);
const MEASURED_ROUNDS = Number(process.env.SPIKE_MEASURED_ROUNDS || 40);
const RACE_ROUNDS = Number(process.env.SPIKE_RACE_ROUNDS || 40);
const MAX_CAS_ATTEMPTS = 20;
const MAX_BODY_BYTES = 4_096;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/;

if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
  throw new Error("Refusing to run without FIREBASE_DATABASE_EMULATOR_HOST");
}

function rootUrl() {
  const host = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  const namespace = `${PROJECT_ID}-default-rtdb`;
  return `http://${host}/${ROOT_PATH}.json?ns=${namespace}`;
}

function questionUrl(matchId) {
  const host = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  const namespace = `${PROJECT_ID}-default-rtdb`;
  return `http://${host}/${ROOT_PATH}/matches/${matchId}.json?ns=${namespace}`;
}

function answerUrl(matchId, playerId) {
  const host = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  const namespace = `${PROJECT_ID}-default-rtdb`;
  return `http://${host}/${ROOT_PATH}/matches/${matchId}/answers/${playerId}.json?ns=${namespace}`;
}

function headers(extra = {}) {
  return {
    authorization: "Bearer owner",
    ...extra,
  };
}

function operationCounter() {
  return {
    reads: 0,
    writeAttempts: 0,
    successfulWrites: 0,
    contentionRetries: 0,
  };
}

function addOperations(target, source) {
  for (const key of Object.keys(target)) {
    target[key] += source[key] || 0;
  }
}

async function readJson(url, operations, includeEtag = false) {
  operations.reads += 1;
  const response = await fetch(url, {
    headers: headers(includeEtag ? { "x-firebase-etag": "true" } : {}),
  });
  if (!response.ok) {
    throw new Error(`RTDB read failed: HTTP ${response.status}`);
  }
  return {
    value: await response.json(),
    etag: response.headers.get("etag"),
  };
}

async function conditionalPut(url, value, etag, operations) {
  operations.writeAttempts += 1;
  const response = await fetch(url, {
    method: "PUT",
    headers: headers({
      "content-type": "application/json",
      "if-match": etag,
    }),
    body: JSON.stringify(value),
  });
  if (response.status === 412) {
    operations.contentionRetries += 1;
    return { contention: true, value: null };
  }
  if (!response.ok) {
    throw new Error(`RTDB conditional write failed: HTTP ${response.status}`);
  }
  operations.successfulWrites += 1;
  return { contention: false, value: await response.json() };
}

async function setQuestion(matchId, state) {
  const response = await fetch(questionUrl(matchId), {
    method: "PUT",
    headers: headers({ "content-type": "application/json" }),
    body: JSON.stringify(state),
  });
  if (!response.ok) {
    throw new Error(`RTDB setup failed: HTTP ${response.status}`);
  }
}

async function readQuestion(matchId) {
  const response = await fetch(questionUrl(matchId), { headers: headers() });
  if (!response.ok) {
    throw new Error(`RTDB verification read failed: HTTP ${response.status}`);
  }
  return response.json();
}

function initialQuestion(model, deadlineOffsetMs = 60_000, answers = {}) {
  return {
    schemaVersion: 1,
    spikeModel: model,
    phase: "QUESTION_OPEN",
    stateVersion: 0,
    globalSequence: 0,
    questionId: "spike-question-1",
    questionOpenedAtEpochMs: Date.now(),
    questionDeadlineEpochMs: Date.now() + deadlineOffsetMs,
    participantOrder: PLAYERS,
    players: Object.fromEntries(
      PLAYERS.map((playerId) => [
        playerId,
        { sessionId: `session-${playerId}`, sessionEpoch: 1 },
      ])
    ),
    validAnswerIds: Object.fromEntries(
      [...VALID_ANSWER_IDS].map((answerId) => [answerId, true])
    ),
    correctAnswerId: CORRECT_ANSWER_ID,
    answers,
  };
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validateAnswerBody(body) {
  const allowed = new Set([
    "model",
    "matchId",
    "questionId",
    "answerId",
    "eventId",
    "sessionId",
    "sessionEpoch",
  ]);
  if (!isPlainObject(body)
      || !Object.keys(body).every((key) => allowed.has(key))
      || ![MODEL_GLOBAL, MODEL_INDEPENDENT].includes(body.model)
      || !SAFE_ID.test(body.matchId || "")
      || !SAFE_ID.test(body.questionId || "")
      || !SAFE_ID.test(body.answerId || "")
      || !SAFE_ID.test(body.eventId || "")
      || !SAFE_ID.test(body.sessionId || "")
      || !Number.isSafeInteger(body.sessionEpoch)
      || body.sessionEpoch < 1) {
    return "MALFORMED_REQUEST";
  }
  return null;
}

function inspectQuestion(state, body, playerId, receivedAtEpochMs) {
  if (!state) return { code: "UNKNOWN_MATCH" };
  if (state.spikeModel !== body.model) return { code: "MODEL_MISMATCH" };
  if (state.questionId !== body.questionId) return { code: "STALE_QUESTION" };
  const player = state.players?.[playerId];
  if (!player) return { code: "UNKNOWN_PLAYER" };
  if (player.sessionId !== body.sessionId
      || player.sessionEpoch !== body.sessionEpoch) {
    return { code: "STALE_SESSION" };
  }
  if (!state.validAnswerIds?.[body.answerId]) {
    return { code: "INVALID_ANSWER" };
  }
  const prior = state.answers?.[playerId];
  if (prior) {
    if (prior.eventId === body.eventId) {
      const acceptedByResult = state.result?.answerEventIds?.[playerId] === body.eventId;
      const acceptedWhileOpen = state.phase === "QUESTION_OPEN"
        && prior.acceptedAtEpochMs <= state.questionDeadlineEpochMs;
      return {
        duplicate: true,
        accepted: acceptedByResult || acceptedWhileOpen,
        code: "DUPLICATE_EVENT",
      };
    }
    return { code: "DUPLICATE_ANSWER" };
  }
  if (state.phase !== "QUESTION_OPEN") return { code: "QUESTION_CLOSED" };
  if (receivedAtEpochMs > state.questionDeadlineEpochMs) {
    return { code: "DEADLINE_EXCEEDED" };
  }
  return null;
}

function answerRecord(body, playerId, acceptedAt) {
  return {
    playerId,
    eventId: body.eventId,
    questionId: body.questionId,
    answerId: body.answerId,
    sessionId: body.sessionId,
    sessionEpoch: body.sessionEpoch,
    acceptedAtEpochMs: acceptedAt,
  };
}

function rejection(code, operations, extra = {}) {
  return { status: "rejected", accepted: false, code, operations, ...extra };
}

async function answerWithGlobalCas(body, playerId, receivedAtEpochMs) {
  const operations = operationCounter();
  for (let attempt = 1; attempt <= MAX_CAS_ATTEMPTS; attempt += 1) {
    const { value: state, etag } = await readJson(
      questionUrl(body.matchId),
      operations,
      true
    );
    const inspection = inspectQuestion(state, body, playerId, receivedAtEpochMs);
    if (inspection) {
      if (inspection.duplicate) {
        return {
          status: "duplicate",
          accepted: inspection.accepted,
          code: inspection.code,
          operations,
        };
      }
      return rejection(inspection.code, operations);
    }

    const sequence = (state.globalSequence || 0) + 1;
    const record = answerRecord(body, playerId, receivedAtEpochMs);
    record.globalSequence = sequence;
    const candidate = {
      ...state,
      globalSequence: sequence,
      stateVersion: (state.stateVersion || 0) + 1,
      answers: { ...(state.answers || {}), [playerId]: record },
    };
    const write = await conditionalPut(
      questionUrl(body.matchId),
      candidate,
      etag,
      operations
    );
    if (write.contention) continue;
    return {
      status: "accepted",
      accepted: true,
      code: null,
      acceptedAtEpochMs: receivedAtEpochMs,
      globalSequence: sequence,
      operations,
    };
  }
  return rejection("CAS_RETRY_EXHAUSTED", operations);
}

async function answerIndependently(body, playerId, receivedAtEpochMs) {
  const operations = operationCounter();
  const initial = await readJson(questionUrl(body.matchId), operations);
  const inspection = inspectQuestion(
    initial.value,
    body,
    playerId,
    receivedAtEpochMs
  );
  if (inspection) {
    if (inspection.duplicate) {
      return {
        status: "duplicate",
        accepted: inspection.accepted,
        code: inspection.code,
        operations,
      };
    }
    return rejection(inspection.code, operations);
  }

  const record = answerRecord(body, playerId, { ".sv": "timestamp" });
  const write = await conditionalPut(
    answerUrl(body.matchId, playerId),
    record,
    "null_etag",
    operations
  );
  if (write.contention) {
    const current = await readJson(answerUrl(body.matchId, playerId), operations);
    if (current.value?.eventId === body.eventId) {
      return {
        status: "duplicate",
        accepted: current.value.acceptedAtEpochMs
          <= initial.value.questionDeadlineEpochMs,
        code: "DUPLICATE_EVENT",
        operations,
      };
    }
    return rejection("DUPLICATE_ANSWER", operations);
  }

  const persisted = write.value;
  const finalRead = await readJson(questionUrl(body.matchId), operations);
  const state = finalRead.value;
  const acceptedAtEpochMs = persisted.acceptedAtEpochMs;
  const includedInResult = state?.result?.answerEventIds?.[playerId]
    === body.eventId;

  if (state?.phase === "QUESTION_RESULT" && !includedInResult) {
    return rejection("QUESTION_CLOSED", operations, { acceptedAtEpochMs });
  }
  if (acceptedAtEpochMs > state.questionDeadlineEpochMs) {
    return rejection("DEADLINE_EXCEEDED", operations, { acceptedAtEpochMs });
  }
  return {
    status: "accepted",
    accepted: true,
    code: null,
    acceptedAtEpochMs,
    operations,
  };
}

function canonicalResult(state, closeReason, closedAtEpochMs) {
  const tieBreak = new Map(
    state.participantOrder.map((playerId, index) => [playerId, index])
  );
  const orderedAnswers = Object.values(state.answers || {})
    .filter((answer) => state.players?.[answer.playerId]
      && answer.questionId === state.questionId
      && Number.isFinite(answer.acceptedAtEpochMs)
      && answer.acceptedAtEpochMs <= state.questionDeadlineEpochMs)
    .sort((left, right) => {
      if (left.acceptedAtEpochMs === right.acceptedAtEpochMs) {
        return tieBreak.get(left.playerId) - tieBreak.get(right.playerId);
      }
      return left.acceptedAtEpochMs - right.acceptedAtEpochMs;
    });

  const scoreDeltas = Object.fromEntries(PLAYERS.map((playerId) => [playerId, 0]));
  const correctPlayerIds = [];
  const wrongPlayerIds = [];
  const correctPoints = [20, 10, 5];
  for (const answer of orderedAnswers) {
    if (answer.answerId === state.correctAnswerId) {
      const rank = correctPlayerIds.length;
      correctPlayerIds.push(answer.playerId);
      scoreDeltas[answer.playerId] = correctPoints[rank] ?? 1;
    } else {
      wrongPlayerIds.push(answer.playerId);
      scoreDeltas[answer.playerId] = -10;
    }
  }
  const answered = new Set(orderedAnswers.map((answer) => answer.playerId));
  const unansweredPlayerIds = PLAYERS.filter((playerId) => !answered.has(playerId));
  return {
    closeReason,
    closedAtEpochMs,
    answerOrder: orderedAnswers.map((answer) => answer.playerId),
    answerEventIds: Object.fromEntries(
      orderedAnswers.map((answer) => [answer.playerId, answer.eventId])
    ),
    correctPlayerIds,
    wrongPlayerIds,
    unansweredPlayerIds,
    scoreDeltas,
  };
}

async function closeQuestion(body) {
  const operations = operationCounter();
  for (let attempt = 1; attempt <= MAX_CAS_ATTEMPTS; attempt += 1) {
    const { value: state, etag } = await readJson(
      questionUrl(body.matchId),
      operations,
      true
    );
    if (!state) return rejection("UNKNOWN_MATCH", operations);
    if (state.questionId !== body.questionId) {
      return rejection("STALE_QUESTION", operations);
    }
    if (state.phase === "QUESTION_RESULT") {
      return {
        status: "duplicate",
        accepted: true,
        code: "ALREADY_CLOSED",
        result: state.result,
        operations,
      };
    }

    const now = Date.now();
    const eligibleAnswers = Object.values(state.answers || {}).filter(
      (answer) => Number.isFinite(answer.acceptedAtEpochMs)
        && answer.acceptedAtEpochMs <= state.questionDeadlineEpochMs
    );
    if (body.reason === "ALL_ANSWERED" && eligibleAnswers.length < PLAYERS.length) {
      return rejection("NOT_ALL_ANSWERED", operations);
    }
    if (body.reason === "DEADLINE" && now <= state.questionDeadlineEpochMs) {
      return rejection("DEADLINE_NOT_REACHED", operations);
    }

    const result = canonicalResult(state, body.reason, now);
    const candidate = {
      ...state,
      phase: "QUESTION_RESULT",
      stateVersion: (state.stateVersion || 0) + 1,
      result,
    };
    const write = await conditionalPut(
      questionUrl(body.matchId),
      candidate,
      etag,
      operations
    );
    if (write.contention) continue;
    return {
      status: "accepted",
      accepted: true,
      code: null,
      result,
      operations,
    };
  }
  return rejection("CAS_RETRY_EXHAUSTED", operations);
}

async function parseBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("REQUEST_TOO_LARGE");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    "content-type": "application/json",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(body));
}

async function createServer() {
  const server = http.createServer(async (request, response) => {
    const t1 = performance.now();
    try {
      if (request.method !== "POST") {
        sendJson(response, 405, { status: "rejected", code: "METHOD_NOT_ALLOWED" });
        return;
      }
      const body = await parseBody(request);
      let decision;
      if (request.url === "/answer") {
        const validationError = validateAnswerBody(body);
        if (validationError) {
          decision = rejection(validationError, operationCounter());
        } else {
          const playerId = request.headers["x-spike-auth-player"];
          if (typeof playerId !== "string" || !PLAYERS.includes(playerId)) {
            decision = rejection("UNAUTHENTICATED", operationCounter());
          } else {
            const receivedAtEpochMs = Date.now();
            decision = body.model === MODEL_GLOBAL
              ? await answerWithGlobalCas(body, playerId, receivedAtEpochMs)
              : await answerIndependently(body, playerId, receivedAtEpochMs);
          }
        }
      } else if (request.url === "/close") {
        decision = await closeQuestion(body);
      } else {
        sendJson(response, 404, { status: "rejected", code: "NOT_FOUND" });
        return;
      }
      sendJson(response, 200, {
        ...decision,
        timing: { t1ToT2Ms: performance.now() - t1 },
      });
    } catch (error) {
      sendJson(response, 500, {
        status: "error",
        code: error.message || "INTERNAL_ERROR",
      });
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server;
}

async function postJson(baseUrl, path, body, playerId = null) {
  const t0 = performance.now();
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(playerId ? { "x-spike-auth-player": playerId } : {}),
    },
    body: JSON.stringify(body),
  });
  const result = await response.json();
  result.t0ToT3Ms = performance.now() - t0;
  return result;
}

function answerBody(model, matchId, playerId, eventId, answerId) {
  return {
    model,
    matchId,
    questionId: "spike-question-1",
    answerId,
    eventId,
    sessionId: `session-${playerId}`,
    sessionEpoch: 1,
  };
}

async function submitAnswer(baseUrl, model, matchId, playerId, eventId, answerId) {
  return postJson(
    baseUrl,
    "/answer",
    answerBody(model, matchId, playerId, eventId, answerId),
    playerId
  );
}

async function close(baseUrl, model, matchId, reason) {
  return postJson(baseUrl, "/close", {
    model,
    matchId,
    questionId: "spike-question-1",
    reason,
  });
}

function nearestRank(values, percentile) {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.max(0, Math.ceil(percentile * sorted.length) - 1);
  return sorted[index];
}

function latencySummary(values) {
  return {
    min: Math.min(...values),
    p50: nearestRank(values, 0.50),
    p95: nearestRank(values, 0.95),
    max: Math.max(...values),
  };
}

async function benchmarkModel(baseUrl, model) {
  const t1ToT2 = [];
  const t0ToT3 = [];
  const answerOperations = operationCounter();
  const closeOperations = operationCounter();
  const totalRounds = WARMUP_ROUNDS + MEASURED_ROUNDS;
  for (let round = 0; round < totalRounds; round += 1) {
    const matchId = `${model === MODEL_GLOBAL ? "global" : "independent"}-${round}`;
    await setQuestion(matchId, initialQuestion(model));
    const answers = await Promise.all(
      PLAYERS.map((playerId, index) => submitAnswer(
        baseUrl,
        model,
        matchId,
        playerId,
        `event-${round}-${playerId}`,
        index % 2 === 0 ? CORRECT_ANSWER_ID : `answer-wrong-${(index % 3) + 1}`
      ))
    );
    for (const answer of answers) {
      assert.equal(answer.status, "accepted");
      assert.equal(answer.accepted, true);
    }
    const closeResult = await close(baseUrl, model, matchId, "ALL_ANSWERED");
    assert.equal(closeResult.accepted, true);
    assert.deepEqual(new Set(closeResult.result.correctPlayerIds), new Set(["A", "C"]));
    assert.deepEqual(
      [closeResult.result.scoreDeltas.A, closeResult.result.scoreDeltas.C]
        .sort((left, right) => right - left),
      [20, 10]
    );
    assert.equal(closeResult.result.scoreDeltas.B, -10);
    assert.equal(closeResult.result.scoreDeltas.D, -10);

    if (round >= WARMUP_ROUNDS) {
      for (const answer of answers) {
        t1ToT2.push(answer.timing.t1ToT2Ms);
        t0ToT3.push(answer.t0ToT3Ms);
        addOperations(answerOperations, answer.operations);
      }
      addOperations(closeOperations, closeResult.operations);
    }
  }
  return {
    rounds: MEASURED_ROUNDS,
    requests: MEASURED_ROUNDS * PLAYERS.length,
    concurrency: PLAYERS.length,
    t1ToT2Ms: latencySummary(t1ToT2),
    t0ToT3Ms: latencySummary(t0ToT3),
    answerOperations,
    closeOperations,
  };
}

async function runDuplicateAndSecurityChecks(baseUrl) {
  const checks = {};
  let matchId = "duplicate-basic";
  await setQuestion(matchId, initialQuestion(MODEL_INDEPENDENT));
  const first = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "event-a",
    CORRECT_ANSWER_ID
  );
  const retry = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "event-a",
    CORRECT_ANSWER_ID
  );
  const second = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "event-a-2",
    CORRECT_ANSWER_ID
  );
  assert.equal(first.status, "accepted");
  assert.equal(retry.status, "duplicate");
  assert.equal(second.code, "DUPLICATE_ANSWER");
  checks.duplicateEvent = "pass";
  checks.duplicateAnswer = "pass";

  matchId = "duplicate-concurrent";
  await setQuestion(matchId, initialQuestion(MODEL_INDEPENDENT));
  const concurrent = await Promise.all([
    submitAnswer(baseUrl, MODEL_INDEPENDENT, matchId, "A", "same-event", CORRECT_ANSWER_ID),
    submitAnswer(baseUrl, MODEL_INDEPENDENT, matchId, "A", "same-event", CORRECT_ANSWER_ID),
  ]);
  assert.equal(concurrent.filter((value) => value.status === "accepted").length, 1);
  assert.equal(concurrent.filter((value) => value.status === "duplicate").length, 1);
  const concurrentState = await readQuestion(matchId);
  assert.equal(Object.keys(concurrentState.answers).length, 1);
  checks.concurrentRetry = "pass";

  matchId = "security-checks";
  await setQuestion(matchId, initialQuestion(MODEL_INDEPENDENT));
  const staleQuestionBody = answerBody(
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "stale-question-event",
    CORRECT_ANSWER_ID
  );
  staleQuestionBody.questionId = "old-question";
  const staleQuestion = await postJson(baseUrl, "/answer", staleQuestionBody, "A");
  assert.equal(staleQuestion.code, "STALE_QUESTION");

  const staleSessionBody = answerBody(
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "stale-session-event",
    CORRECT_ANSWER_ID
  );
  staleSessionBody.sessionEpoch = 0;
  const staleSession = await postJson(baseUrl, "/answer", staleSessionBody, "A");
  assert.equal(staleSession.code, "MALFORMED_REQUEST");

  const wrongSessionBody = answerBody(
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "wrong-session-event",
    CORRECT_ANSWER_ID
  );
  wrongSessionBody.sessionId = "session-B";
  const wrongSession = await postJson(baseUrl, "/answer", wrongSessionBody, "A");
  assert.equal(wrongSession.code, "STALE_SESSION");

  const invalidAnswer = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "invalid-answer-event",
    "answer-unknown"
  );
  assert.equal(invalidAnswer.code, "INVALID_ANSWER");

  const forgedBody = answerBody(
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "forged-result-event",
    CORRECT_ANSWER_ID
  );
  forgedBody.scoreDelta = 999;
  forgedBody.correct = true;
  const forged = await postJson(baseUrl, "/answer", forgedBody, "A");
  assert.equal(forged.code, "MALFORMED_REQUEST");

  const impersonationBody = answerBody(
    MODEL_INDEPENDENT,
    matchId,
    "A",
    "impersonation-event",
    CORRECT_ANSWER_ID
  );
  impersonationBody.playerId = "B";
  const impersonation = await postJson(baseUrl, "/answer", impersonationBody, "A");
  assert.equal(impersonation.code, "MALFORMED_REQUEST");
  checks.staleQuestion = "pass";
  checks.wrongSession = "pass";
  checks.invalidAnswer = "pass";
  checks.clientResultFields = "pass";
  checks.otherPlayerTarget = "pass";
  return checks;
}

async function runScoreChecks(baseUrl) {
  const results = {};

  async function allAnsweredScenario(name, answerIds, expected) {
    await setQuestion(name, initialQuestion(MODEL_INDEPENDENT));
    for (const [index, playerId] of PLAYERS.entries()) {
      await submitAnswer(
        baseUrl,
        MODEL_INDEPENDENT,
        name,
        playerId,
        `${name}-${playerId}`,
        answerIds[index]
      );
      await new Promise((resolve) => setTimeout(resolve, 2));
    }
    const closed = await close(baseUrl, MODEL_INDEPENDENT, name, "ALL_ANSWERED");
    assert.deepEqual(closed.result.scoreDeltas, expected);
    return closed.result;
  }

  results.oneCorrect = await allAnsweredScenario(
    "score-one-correct",
    [CORRECT_ANSWER_ID, "answer-wrong-1", "answer-wrong-2", "answer-wrong-3"],
    { A: 20, B: -10, C: -10, D: -10 }
  );
  results.fourCorrect = await allAnsweredScenario(
    "score-four-correct",
    PLAYERS.map(() => CORRECT_ANSWER_ID),
    { A: 20, B: 10, C: 5, D: 1 }
  );
  results.allWrong = await allAnsweredScenario(
    "score-all-wrong",
    PLAYERS.map(() => "answer-wrong-1"),
    { A: -10, B: -10, C: -10, D: -10 }
  );

  const partialMatch = "score-partial";
  await setQuestion(partialMatch, initialQuestion(MODEL_INDEPENDENT, 80));
  await submitAnswer(baseUrl, MODEL_INDEPENDENT, partialMatch, "A", "partial-a", CORRECT_ANSWER_ID);
  await submitAnswer(baseUrl, MODEL_INDEPENDENT, partialMatch, "B", "partial-b", "answer-wrong-1");
  await submitAnswer(baseUrl, MODEL_INDEPENDENT, partialMatch, "C", "partial-c", CORRECT_ANSWER_ID);
  await new Promise((resolve) => setTimeout(resolve, 90));
  const partialClosed = await close(
    baseUrl,
    MODEL_INDEPENDENT,
    partialMatch,
    "DEADLINE"
  );
  assert.deepEqual(partialClosed.result.scoreDeltas, { A: 20, B: -10, C: 10, D: 0 });
  results.partial = partialClosed.result;

  const noAnswerMatch = "score-no-answer";
  await setQuestion(noAnswerMatch, initialQuestion(MODEL_INDEPENDENT, -1));
  const noAnswerClosed = await close(
    baseUrl,
    MODEL_INDEPENDENT,
    noAnswerMatch,
    "DEADLINE"
  );
  assert.deepEqual(noAnswerClosed.result.scoreDeltas, { A: 0, B: 0, C: 0, D: 0 });
  results.noAnswer = noAnswerClosed.result;

  const tieMatch = "score-tie";
  const tieEpochMs = Date.now();
  const tiedAnswers = Object.fromEntries(
    ["D", "C", "B", "A"].map((playerId) => [
      playerId,
      answerRecord(
        answerBody(
          MODEL_INDEPENDENT,
          tieMatch,
          playerId,
          `tie-${playerId}`,
          CORRECT_ANSWER_ID
        ),
        playerId,
        tieEpochMs
      ),
    ])
  );
  await setQuestion(tieMatch, initialQuestion(MODEL_INDEPENDENT, 60_000, tiedAnswers));
  const tieClosed = await close(baseUrl, MODEL_INDEPENDENT, tieMatch, "ALL_ANSWERED");
  assert.deepEqual(tieClosed.result.answerOrder, PLAYERS);
  assert.deepEqual(tieClosed.result.scoreDeltas, { A: 20, B: 10, C: 5, D: 1 });
  results.tie = tieClosed.result;
  return results;
}

async function runDeadlineChecks(baseUrl) {
  const beforeMatch = "deadline-before";
  await setQuestion(beforeMatch, initialQuestion(MODEL_INDEPENDENT, 80));
  const before = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    beforeMatch,
    "A",
    "before-event",
    CORRECT_ANSWER_ID
  );
  assert.equal(before.status, "accepted");
  await new Promise((resolve) => setTimeout(resolve, 90));
  const beforeClosed = await close(
    baseUrl,
    MODEL_INDEPENDENT,
    beforeMatch,
    "DEADLINE"
  );
  assert.equal(beforeClosed.result.answerEventIds.A, "before-event");

  const afterMatch = "deadline-after";
  await setQuestion(afterMatch, initialQuestion(MODEL_INDEPENDENT, -1));
  const after = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    afterMatch,
    "A",
    "after-event",
    CORRECT_ANSWER_ID
  );
  assert.equal(after.code, "DEADLINE_EXCEEDED");
  const afterClosed = await close(baseUrl, MODEL_INDEPENDENT, afterMatch, "DEADLINE");
  assert.equal(afterClosed.result.answerEventIds.A, undefined);
  const afterResult = await submitAnswer(
    baseUrl,
    MODEL_INDEPENDENT,
    afterMatch,
    "B",
    "after-result-event",
    CORRECT_ANSWER_ID
  );
  assert.equal(afterResult.code, "QUESTION_CLOSED");

  let accepted = 0;
  let rejected = 0;
  let closeRetries = 0;
  for (let round = 0; round < RACE_ROUNDS; round += 1) {
    const matchId = `deadline-race-${round}`;
    await setQuestion(matchId, initialQuestion(MODEL_INDEPENDENT, 20));
    const answerPromise = new Promise((resolve) => {
      setTimeout(() => resolve(submitAnswer(
        baseUrl,
        MODEL_INDEPENDENT,
        matchId,
        "A",
        `race-event-${round}`,
        CORRECT_ANSWER_ID
      )), 15);
    }).then((value) => value);
    let closePromise = new Promise((resolve) => {
      setTimeout(() => resolve(close(
        baseUrl,
        MODEL_INDEPENDENT,
        matchId,
        "DEADLINE"
      )), 21);
    }).then((value) => value);
    const answerResult = await answerPromise;
    let closeResult = await closePromise;
    if (closeResult.code === "DEADLINE_NOT_REACHED") {
      closeRetries += 1;
      await new Promise((resolve) => setTimeout(resolve, 2));
      closeResult = await close(baseUrl, MODEL_INDEPENDENT, matchId, "DEADLINE");
    }
    assert.equal(closeResult.accepted, true);
    const included = closeResult.result.answerEventIds.A === `race-event-${round}`;
    if (answerResult.accepted) {
      accepted += 1;
      assert.equal(included, true);
    } else {
      rejected += 1;
      assert.equal(included, false);
    }
    const closedState = await readQuestion(matchId);
    const immutableResult = closedState.result;
    const late = await submitAnswer(
      baseUrl,
      MODEL_INDEPENDENT,
      matchId,
      "B",
      `late-event-${round}`,
      CORRECT_ANSWER_ID
    );
    assert.equal(late.accepted, false);
    const finalState = await readQuestion(matchId);
    assert.deepEqual(finalState.result, immutableResult);
  }
  return {
    beforeDeadline: "accepted-and-included",
    afterDeadline: "rejected-and-excluded",
    afterResult: "rejected-result-immutable",
    raceRounds: RACE_ROUNDS,
    raceAccepted: accepted,
    raceRejected: rejected,
    closeNotDueRetries: closeRetries,
  };
}

async function cleanup() {
  const response = await fetch(rootUrl(), {
    method: "DELETE",
    headers: headers(),
  });
  if (!response.ok) throw new Error(`Spike cleanup failed: HTTP ${response.status}`);
  const readback = await fetch(rootUrl(), { headers: headers() });
  assert.equal(await readback.json(), null);
}

async function main() {
  const server = await createServer();
  const address = server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;
  try {
    await cleanup();
    const global = await benchmarkModel(baseUrl, MODEL_GLOBAL);
    const independent = await benchmarkModel(baseUrl, MODEL_INDEPENDENT);
    const duplicateAndSecurity = await runDuplicateAndSecurityChecks(baseUrl);
    const scores = await runScoreChecks(baseUrl);
    const deadline = await runDeadlineChecks(baseUrl);
    const report = {
      environment: {
        project: PROJECT_ID,
        rtdb: process.env.FIREBASE_DATABASE_EMULATOR_HOST,
        driver: "local macOS Node.js",
        warmupRounds: WARMUP_ROUNDS,
        measuredRounds: MEASURED_ROUNDS,
        concurrency: PLAYERS.length,
      },
      models: { globalSequenceCas: global, independentCloseOrder: independent },
      duplicateAndSecurity,
      scoreChecks: {
        oneCorrect: scores.oneCorrect.scoreDeltas,
        fourCorrect: scores.fourCorrect.scoreDeltas,
        allWrong: scores.allWrong.scoreDeltas,
        partial: scores.partial.scoreDeltas,
        allNoAnswer: scores.noAnswer.scoreDeltas,
        exactTimestampTieOrder: scores.tie.answerOrder,
      },
      deadline,
      cleanup: "pass-readback-null",
    };
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } finally {
    await cleanup();
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
