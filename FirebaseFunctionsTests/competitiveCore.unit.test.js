const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { PROTOCOL_VERSION, PHASE } = require("../functions/competitive/constants");
const { validateClientIntent } = require("../functions/competitive/contract");
const {
  processClientIntent,
  processReconcile,
  syncPublic,
} = require("../functions/competitive/core");
const { scoreQuestion } = require("../functions/competitive/scoring");
const { buildTestMatch } = require("../functions/competitive/testMatchFactory");

const rootDir = path.resolve(__dirname, "..");
const players = [1, 2, 3, 4].map((number) => ({
  uid: `p${number}`,
  displayName: `Player ${number}`,
  sessionId: `session-p${number}`,
  sessionEpoch: 1,
  assignmentTicket: `ticket-p${number}`,
}));

function envelope(type, player, sequence, overrides = {}) {
  return {
    intentId: `event-${type}-${player.uid}-${sequence}`,
    type,
    protocolVersion: PROTOCOL_VERSION,
    clientBuild: "phase-a2-test",
    sessionId: player.sessionId,
    sessionEpoch: player.sessionEpoch,
    matchId: "match-unit",
    lastSeenServerSequence: 0,
    payload: {},
    ...overrides,
  };
}

function applyClient(match, player, event, now, stagedAnswer = null, stageError = null) {
  const result = processClientIntent(match, event, player.uid, now, stagedAnswer, stageError);
  return result;
}

function applyReconcile(match, player, sequence, now) {
  const event = envelope("reconcile", player, sequence);
  return processReconcile(match, event, player.uid, now);
}

function waitingMatch() {
  let match = buildTestMatch({ matchId: "match-unit", players, createdAtEpochMs: 1_000 });
  match = applyReconcile(match, players[0], "created", 1_001).match;
  return match;
}

function openMatch() {
  let match = waitingMatch();
  for (const [index, player] of players.entries()) {
    match = applyClient(
      match,
      player,
      envelope("joinMatch", player, `join-${index}`, {
        payload: { assignmentTicket: player.assignmentTicket },
      }),
      1_010 + index
    ).match;
    match = applyClient(
      match,
      player,
      envelope("ready", player, `ready-${index}`),
      1_020 + index
    ).match;
  }
  assert.equal(match.private.phase, PHASE.COUNTDOWN);
  match = applyReconcile(match, players[0], "open", 2_000).match;
  assert.equal(match.private.phase, PHASE.QUESTION_OPEN);
  return match;
}

describe("Competitive Core unit", () => {
  it("matches the existing friend-battle scoring fixture", () => {
    const fixture = JSON.parse(fs.readFileSync(
      path.join(rootDir, "fixtures/competitive-v2-scoring.json"),
      "utf8"
    ));

    for (const testCase of fixture.cases) {
      const answers = Object.fromEntries(testCase.answers.map((answer, index) => [
        answer.uid,
        {
          uid: answer.uid,
          eventId: `fixture-${index}`,
          answerId: answer.answer,
          acceptedAtEpochMs: answer.timestamp,
        },
      ]));
      const result = scoreQuestion({
        answers,
        participantOrder: fixture.participantOrder,
        deadlineEpochMs: Number.MAX_SAFE_INTEGER,
        correctAnswerId: fixture.correctAnswer,
      });

      assert.deepEqual(result.correctUIDs, testCase.correctUIDs, testCase.name);
      assert.deepEqual(result.wrongUIDs, testCase.wrongUIDs, testCase.name);
      assert.deepEqual(result.scoreDeltas, testCase.scoreDeltas, testCase.name);
    }
  });

  it("validates the strict client intent contract", () => {
    const player = players[0];
    const valid = envelope("submitAnswer", player, 1, {
      questionId: "question-1",
      stateVersion: 3,
      payload: { answerId: "answer-1" },
    });
    assert.equal(validateClientIntent(valid), null);
    assert.equal(validateClientIntent({ ...valid, score: 999 }), "INVALID_PAYLOAD");
    assert.equal(validateClientIntent({
      ...valid,
      payload: { answerId: "answer-1", acceptedAtEpochMs: 0 },
    }), "INVALID_PAYLOAD");
    assert.equal(validateClientIntent({ ...valid, protocolVersion: "old" }), "PROTOCOL_UNSUPPORTED");
  });

  it("runs join ready answer result transitions with a sanitized projection", () => {
    let match = openMatch();
    const question = match.private.currentQuestion;
    const stateVersion = match.private.stateVersion;

    for (const [index, player] of players.entries()) {
      const answerId = index === 3
        ? question.choices.find((choice) => choice.answerId !== question.correctAnswerId).answerId
        : question.correctAnswerId;
      const event = envelope("submitAnswer", player, `answer-${index}`, {
        questionId: question.questionId,
        stateVersion,
        payload: { answerId },
      });
      const staged = {
        uid: player.uid,
        eventId: event.intentId,
        questionId: question.questionId,
        answerId,
        acceptedAtEpochMs: 2_100 + index,
      };
      const result = applyClient(match, player, event, 2_200 + index, staged);
      assert.equal(result.ack.status, "ACCEPTED");
      match = result.match;
    }

    assert.equal(match.private.phase, PHASE.QUESTION_RESULT);
    assert.deepEqual(match.private.currentQuestion.result.correctUIDs, ["p1", "p2", "p3"]);
    assert.deepEqual(match.private.currentQuestion.result.scoreDeltas, {
      p1: 20, p2: 10, p3: 5, p4: -10,
    });
    assert.equal(match.public.currentQuestion.correctAnswerId, question.correctAnswerId);
    assert.equal(JSON.stringify(match.public).includes("canonicalId"), false);
    assert.equal(JSON.stringify(match.public).includes("assignmentTicket"), false);
    assert.equal(JSON.stringify(match.public).includes("answerInbox"), false);
  });

  it("makes retries idempotent and rejects changed replay payloads", () => {
    let match = openMatch();
    const player = players[0];
    const question = match.private.currentQuestion;
    const event = envelope("submitAnswer", player, "stable", {
      questionId: question.questionId,
      stateVersion: match.private.stateVersion,
      payload: { answerId: question.correctAnswerId },
    });
    const staged = {
      uid: player.uid,
      eventId: event.intentId,
      questionId: question.questionId,
      answerId: question.correctAnswerId,
      acceptedAtEpochMs: 2_100,
    };
    const first = applyClient(match, player, event, 2_101, staged);
    match = first.match;
    const sequence = match.private.serverSequence;
    const duplicate = applyClient(match, player, event, 2_102, staged);
    const altered = applyClient(match, player, {
      ...event,
      payload: { answerId: question.choices.find(
        (choice) => choice.answerId !== question.correctAnswerId
      ).answerId },
    }, 2_103, staged);

    assert.equal(duplicate.ack.status, "DUPLICATE");
    assert.equal(duplicate.match.private.serverSequence, sequence);
    assert.equal(altered.ack.rejectionCode, "INTENT_REPLAY_MISMATCH");
    assert.equal(altered.match.private.serverSequence, sequence);
  });

  it("rejects stale and deadline-late answers without changing scores", () => {
    let match = openMatch();
    const player = players[0];
    const question = match.private.currentQuestion;
    const event = envelope("submitAnswer", player, "late", {
      questionId: question.questionId,
      stateVersion: question.openedStateVersion - 1,
      payload: { answerId: question.correctAnswerId },
    });
    const staged = {
      uid: player.uid,
      eventId: event.intentId,
      questionId: question.questionId,
      answerId: question.correctAnswerId,
      acceptedAtEpochMs: question.deadlineEpochMs + 1,
    };
    let result = applyClient(match, player, event, question.deadlineEpochMs + 2, staged);
    assert.equal(result.ack.rejectionCode, "STALE_STATE_VERSION");
    match = result.match;

    const lateEvent = { ...event, intentId: "event-submitAnswer-p1-late-2", stateVersion: match.private.stateVersion };
    result = applyClient(match, player, lateEvent, question.deadlineEpochMs + 3, {
      ...staged,
      eventId: lateEvent.intentId,
    });
    assert.equal(result.ack.rejectionCode, "DEADLINE_EXCEEDED");
    assert.equal(result.match.private.scores.p1, 0);
  });

  it("keeps the answer key private while a question is open", () => {
    const match = openMatch();
    syncPublic(match);
    assert.equal(match.private.phase, PHASE.QUESTION_OPEN);
    assert.equal(match.public.currentQuestion.correctAnswerId, undefined);
    assert.equal(JSON.stringify(match.public).includes(match.private.currentQuestion.correctAnswerId), true,
      "all answer IDs are choices, but the projection does not identify which one is correct");
    assert.equal(Object.hasOwn(match.public.currentQuestion, "correctAnswerId"), false);
  });
});
