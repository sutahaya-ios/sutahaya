const { randomUUID } = require("node:crypto");
const {
  CONFIG_VERSION,
  PHASE,
  PLAYER_COUNT,
  PROTOCOL_VERSION,
  SERVER_VERSION,
} = require("./constants");
const { TEST_QUESTION_BANK } = require("./questionBank");

function buildQuestionInstances(matchId) {
  return TEST_QUESTION_BANK.map((question, index) => {
    const choices = question.choices.map((text) => ({
      answerId: `a-${index + 1}-${randomUUID()}`,
      text,
    }));
    return {
      canonicalId: question.canonicalId,
      questionId: `q-${index + 1}-${randomUUID()}`,
      prompt: question.prompt,
      choices,
      correctAnswerId: choices[question.correctChoiceIndex].answerId,
      matchId,
    };
  });
}

function buildTestMatch({
  matchId,
  players,
  createdAtEpochMs,
  countdownDurationMs = 10,
  questionDurationMs = 5_000,
  resultDurationMs = 10,
}) {
  if (!Array.isArray(players) || players.length !== PLAYER_COUNT) {
    throw new Error("Competitive Phase A-2 test match requires exactly four players");
  }
  const participantOrder = players.map((player) => player.uid);
  const participants = Object.fromEntries(players.map((player, slot) => [player.uid, {
    uid: player.uid,
    slot,
    displayName: player.displayName || `Player ${slot + 1}`,
    sessionId: player.sessionId,
    sessionEpoch: player.sessionEpoch,
    assignmentTicket: player.assignmentTicket,
    joined: false,
    ready: false,
    active: true,
    forfeited: false,
  }]));

  return {
    private: {
      matchId,
      phase: PHASE.CREATED,
      stateVersion: 0,
      serverSequence: 0,
      phaseOpenedStateVersion: 0,
      protocolVersion: PROTOCOL_VERSION,
      serverVersion: SERVER_VERSION,
      configVersion: CONFIG_VERSION,
      createdAtEpochMs,
      participantOrder,
      participants,
      scores: Object.fromEntries(participantOrder.map((uid) => [uid, 0])),
      questionInstances: buildQuestionInstances(matchId),
      currentQuestionIndex: -1,
      currentQuestion: null,
      intentResults: {},
      audit: {},
      config: {
        countdownDurationMs,
        questionDurationMs,
        resultDurationMs,
      },
    },
  };
}

module.exports = { buildTestMatch };
