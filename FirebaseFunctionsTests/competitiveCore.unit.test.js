const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { PROTOCOL_VERSION, PHASE } = require("../functions/competitive/constants");
const { validateClientIntent } = require("../functions/competitive/contract");
const {
  acceptedAnswersForCurrentQuestion,
  processClientIntent,
  processPresenceSignal,
  processReconcile,
  syncPublic,
} = require("../functions/competitive/core");
const { scoreQuestion } = require("../functions/competitive/scoring");
const { buildCompetitiveMatch } = require("../functions/competitive/matchFactory");
const { npcSkillInputForRating } = require("../functions/competitive/rating");
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

  it("scores only accepted create-only inbox records at deadline close", () => {
    let match = openMatch();
    const question = match.private.currentQuestion;
    match.private.answerInbox = {
      [question.questionId]: {
        p1: {
          uid: "p1",
          eventId: "accepted-p1",
          questionId: question.questionId,
          answerId: question.correctAnswerId,
          acceptedAtEpochMs: question.openedAtEpochMs + 10,
          status: "ACCEPTED",
        },
        p2: {
          uid: "p2",
          eventId: "rejected-p2",
          questionId: question.questionId,
          answerId: question.correctAnswerId,
          acceptedAtEpochMs: question.openedAtEpochMs + 20,
          status: "REJECTED",
          rejectionCode: "INVALID_MATCH_STATE",
        },
        p3: {
          uid: "p3",
          eventId: "late-p3",
          questionId: question.questionId,
          answerId: question.correctAnswerId,
          acceptedAtEpochMs: question.deadlineEpochMs + 1,
          status: "REJECTED",
          rejectionCode: "DEADLINE_EXCEEDED",
        },
      },
    };

    assert.deepEqual(Object.keys(acceptedAnswersForCurrentQuestion(match.private)), ["p1"]);
    const result = applyReconcile(
      match,
      players[0],
      "deadline-with-inbox",
      question.deadlineEpochMs + 1
    );
    match = result.match;

    assert.equal(match.private.phase, PHASE.QUESTION_RESULT);
    assert.deepEqual(match.private.currentQuestion.result.correctUIDs, ["p1"]);
    assert.deepEqual(match.private.currentQuestion.result.unansweredUIDs, ["p2", "p3", "p4"]);
    assert.deepEqual(match.private.currentQuestion.result.scoreDeltas, {
      p1: 20, p2: 0, p3: 0, p4: 0,
    });
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

  it("separates reconnect grace from explicit forfeit and fences the same session", () => {
    let match = openMatch();
    const disconnectedAt = 3_000;
    let presence = processPresenceSignal(match, {
      status: "DISCONNECTED",
      sessionId: players[0].sessionId,
      sessionEpoch: players[0].sessionEpoch,
      authorityEventKey: "2026-01-01T00:00:02.000Z",
    }, players[0].uid, disconnectedAt);
    assert.equal(presence.changed, true);
    match = presence.match;
    assert.equal(match.private.participants.p1.status, "RECONNECTING");
    assert.equal(match.private.participants.p1.reconnectDeadlineEpochMs, 18_000);
    const staleConnected = processPresenceSignal(match, {
      status: "CONNECTED",
      sessionId: players[0].sessionId,
      sessionEpoch: players[0].sessionEpoch,
      authorityEventKey: "2026-01-01T00:00:01.000Z",
    }, players[0].uid, disconnectedAt - 1);
    assert.equal(staleConnected.rejectionCode, "STALE_PRESENCE_EVENT");
    assert.equal(staleConnected.match.private.participants.p1.status, "RECONNECTING");

    const resumed = applyClient(
      match,
      players[0],
      envelope("reconnect", players[0], "within-grace"),
      17_999
    );
    assert.equal(resumed.ack.status, "ACCEPTED");
    assert.equal(resumed.match.private.participants.p1.status, "CONNECTED");

    presence = processPresenceSignal(resumed.match, {
      status: "DISCONNECTED",
      sessionId: players[0].sessionId,
      sessionEpoch: players[0].sessionEpoch,
      authorityEventKey: "2026-01-01T00:00:03.000Z",
    }, players[0].uid, 20_000);
    const expired = applyReconcile(presence.match, players[1], "expire-grace", 35_001);
    assert.equal(expired.match.private.participants.p1.status, "FORFEITED");
    assert.equal(expired.match.private.participants.p1.forfeitReason, "RECONNECT_TIMEOUT");

    const finished = openMatch();
    finished.private.phase = PHASE.MATCH_FINISHED;
    assert.equal(applyClient(
      finished,
      players[0],
      envelope("reconnect", players[0], "after-finish"),
      40_000
    ).ack.rejectionCode, "INVALID_MATCH_STATE");
  });

  it("accepts explicit forfeit during countdown and keeps the remaining roster active", () => {
    let match = waitingMatch();
    for (const [index, player] of players.entries()) {
      match = applyClient(match, player, envelope("joinMatch", player, `countdown-join-${index}`, {
        payload: { assignmentTicket: player.assignmentTicket },
      }), 1_010 + index).match;
      match = applyClient(
        match,
        player,
        envelope("ready", player, `countdown-ready-${index}`),
        1_020 + index
      ).match;
    }
    assert.equal(match.private.phase, PHASE.COUNTDOWN);
    const result = applyClient(
      match,
      players[0],
      envelope("forfeit", players[0], "during-countdown"),
      1_030
    );
    assert.equal(result.ack.status, "ACCEPTED");
    assert.equal(result.match.private.participants.p1.status, "FORFEITED");
    assert.equal(result.match.private.phase, PHASE.COUNTDOWN);
    assert.ok(result.match.private.participants.p2.active);
    assert.equal(result.match.public.participants.p1, undefined);
    assert.deepEqual(result.match.public.forfeitedUIDs, ["p1"]);
    assert.equal(result.match.private.participants.p1.joined, undefined);
    assert.equal(result.match.private.participants.p1.ready, undefined);
    assert.equal(result.match.private.participants.p1.assignmentTicket, undefined);
    assert.equal(result.match.private.participants.p1.uid, "p1");
    assert.equal(result.match.private.participants.p1.sessionId, players[0].sessionId);
  });

  it("freezes an explicit forfeiter score and removes it from live projections", () => {
    let match = openMatch();
    match.private.scores.p1 = 20;
    const question = match.private.currentQuestion;
    const event = envelope("submitAnswer", players[0], "before-forfeit", {
      questionId: question.questionId,
      stateVersion: match.private.stateVersion,
      payload: { answerId: question.correctAnswerId },
    });
    match = applyClient(match, players[0], event, 2_100, {
      uid: "p1",
      eventId: event.intentId,
      questionId: question.questionId,
      answerId: question.correctAnswerId,
      acceptedAtEpochMs: 2_100,
      status: "ACCEPTED",
    }).match;
    const forfeited = applyClient(
      match,
      players[0],
      envelope("forfeit", players[0], "explicit"),
      2_200
    );
    assert.equal(forfeited.ack.status, "ACCEPTED");
    match = applyReconcile(
      forfeited.match,
      players[1],
      "close-after-forfeit",
      question.deadlineEpochMs + 1
    ).match;
    assert.equal(match.private.scores.p1, 20);
    assert.equal(match.private.currentQuestion.result.scoreDeltas.p1, undefined);
    assert.ok(match.private.participantOrder.includes("p1"));
    assert.equal(match.public.participants.p1, undefined);
    assert.equal(match.public.questionResult.scoreDeltas.p1, undefined);
    assert.ok(!match.public.questionResult.unansweredUIDs.includes("p1"));
  });

  it("continues once every remaining live player answered after a forfeit", () => {
    let match = openMatch();
    const question = match.private.currentQuestion;
    for (const [index, player] of players.slice(1).entries()) {
      const event = envelope("submitAnswer", player, `remaining-${index}`, {
        questionId: question.questionId,
        stateVersion: match.private.stateVersion,
        payload: { answerId: question.correctAnswerId },
      });
      match = applyClient(match, player, event, 2_100 + index, {
        uid: player.uid,
        eventId: event.intentId,
        questionId: question.questionId,
        answerId: question.correctAnswerId,
        acceptedAtEpochMs: 2_100 + index,
        status: "ACCEPTED",
      }).match;
    }
    assert.equal(match.private.phase, PHASE.QUESTION_OPEN);
    match = applyClient(
      match,
      players[0],
      envelope("forfeit", players[0], "close-live-denominator"),
      2_200
    ).match;
    assert.equal(match.private.phase, PHASE.QUESTION_RESULT);
    assert.deepEqual(match.private.currentQuestion.result.correctUIDs, ["p2", "p3", "p4"]);
    assert.ok(!match.private.currentQuestion.result.unansweredUIDs.includes("p1"));
  });

  it("uses server-owned NPC actions with correct, wrong, and unanswered outcomes", () => {
    const mixedPlayers = [players[0], ...[1, 2, 3].map((slot) => ({
      uid: `npc:unit:${slot}`,
      kind: "NPC",
      displayName: `NPC ${slot}`,
    }))];
    let match = buildTestMatch({
      matchId: "match-unit",
      players: mixedPlayers,
      createdAtEpochMs: 1_000,
      countdownDurationMs: 1,
      questionDurationMs: 1_000,
    });
    match = applyReconcile(match, players[0], "npc-created", 1_001).match;
    match = applyClient(match, players[0], envelope("joinMatch", players[0], "npc-join", {
      payload: { assignmentTicket: players[0].assignmentTicket },
    }), 1_002).match;
    match = applyClient(match, players[0], envelope("ready", players[0], "npc-ready"), 1_003).match;
    match = applyReconcile(match, players[0], "npc-open", 1_004).match;
    match = applyReconcile(match, players[0], "npc-deadline", 2_005).match;

    const result = match.private.currentQuestion.result;
    assert.ok(result.correctUIDs.some((uid) => uid.startsWith("npc:")));
    assert.ok(result.wrongUIDs.some((uid) => uid.startsWith("npc:")));
    assert.ok(result.unansweredUIDs.some((uid) => uid.startsWith("npc:")));
    assert.equal(match.public.participants["npc:unit:1"].kind, "NPC");
  });

  it("uses production countdown, Bronze question, result, and NPC answer timing", () => {
    const mixedPlayers = [players[0], ...[1, 2, 3].map((slot) => ({
      uid: `npc:timing:${slot}`,
      kind: "NPC",
      displayName: `NPC ${slot}`,
    }))];
    let match = buildCompetitiveMatch({
      matchId: "match-unit",
      players: mixedPlayers,
      createdAtEpochMs: 1_000,
      npcSkillInput: npcSkillInputForRating(1_000),
    });
    assert.equal(match.private.config.countdownDurationMs, 3_000);
    assert.equal(match.private.config.questionDurationMs, 8_000);
    assert.equal(match.private.config.resultDurationMs, 3_000);

    match = applyReconcile(match, players[0], "timing-created", 1_001).match;
    match = applyClient(match, players[0], envelope("joinMatch", players[0], "timing-join", {
      payload: { assignmentTicket: players[0].assignmentTicket },
    }), 1_002).match;
    match = applyClient(match, players[0], envelope("ready", players[0], "timing-ready"), 1_003).match;
    match = applyReconcile(match, players[0], "timing-open", 4_004).match;

    const question = match.private.currentQuestion;
    for (const plan of Object.values(question.npcPlans)) {
      const remainingMs = question.deadlineEpochMs - plan.acceptedAtEpochMs;
      assert.ok(remainingMs <= 3_000 && remainingMs >= 2_900);
    }
  });
});
