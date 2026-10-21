const { randomUUID } = require("node:crypto");
const {
  CONFIG_VERSION,
  PARTICIPANT_KIND,
  PARTICIPANT_STATUS,
  PHASE,
  PLAYER_COUNT,
  PROTOCOL_VERSION,
  SERVER_VERSION,
  RECONNECT_GRACE_MS,
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

function buildCompetitiveMatch({
  matchId,
  players,
  createdAtEpochMs,
  countdownDurationMs = 10,
  questionDurationMs = 5_000,
  resultDurationMs = 10,
  reconnectGraceMs = RECONNECT_GRACE_MS,
  requiresActiveSessionFence = false,
  npcSkillInput = null,
}) {
  if (!Array.isArray(players) || players.length !== PLAYER_COUNT) {
    throw new Error("Competitive match requires exactly four players");
  }
  const participantOrder = players.map((player) => player.uid);
  const participants = Object.fromEntries(players.map((player, slot) => {
    const kind = player.kind === PARTICIPANT_KIND.NPC
      ? PARTICIPANT_KIND.NPC
      : PARTICIPANT_KIND.HUMAN;
    const isNPC = kind === PARTICIPANT_KIND.NPC;
    return [player.uid, {
      uid: player.uid,
      slot,
      kind,
      displayName: player.displayName || (isNPC ? `NPC ${slot + 1}` : `Player ${slot + 1}`),
      ...(isNPC ? {} : {
        sessionId: player.sessionId,
        sessionEpoch: player.sessionEpoch,
        assignmentTicket: player.assignmentTicket,
      }),
      joined: isNPC,
      ready: isNPC,
      active: true,
      forfeited: false,
      status: PARTICIPANT_STATUS.CONNECTED,
    }];
  }));

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
      requiresActiveSessionFence,
      intentResults: {},
      audit: {},
      config: {
        countdownDurationMs,
        questionDurationMs,
        resultDurationMs,
        reconnectGraceMs,
        npcSkillInput: npcSkillInput || {
          profileVersion: "phase-c-fixed-test-1",
          reactionBaseMs: 250,
        },
      },
    },
  };
}

module.exports = { buildCompetitiveMatch };
