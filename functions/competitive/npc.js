const { createHash } = require("node:crypto");

const NPC_PROFILE_VERSION = "competitive-npc-profile-v2";
const NPC_PROFILE_CONFIG = Object.freeze({
  accuracyOffsetsPermille: Object.freeze([-30, -10, 10, 30]),
  attemptOffsetsPermille: Object.freeze([-15, -5, 5, 15]),
  reactionOffsetsMs: Object.freeze([-300, -100, 100, 300]),
  questionJitterMs: 100,
  remainingTargetQuestionJitterMs: 400,
  fastQuestionModulo: 45,
  minimumAnswerElapsedMs: 100,
  deadlineSafetyMs: 100,
});

function clamp(value, lower, upper) {
  return Math.min(upper, Math.max(lower, value));
}

function deterministicInteger(...parts) {
  return createHash("sha256")
    .update(parts.map((part) => String(part)).join("\u001f"))
    .digest()
    .readUInt32BE(0);
}

function rotatedOffset(values, matchId, slot, namespace) {
  const rotation = deterministicInteger(matchId, namespace) % values.length;
  return values[(rotation + slot) % values.length];
}

function npcParticipants(participants) {
  const values = Array.isArray(participants) ? participants : Object.values(participants || {});
  return values
    .filter((participant) => participant.kind === "NPC")
    .sort((left, right) => left.slot - right.slot || left.uid.localeCompare(right.uid));
}

function buildNPCProfiles({ matchId, participants }) {
  const npcs = npcParticipants(participants);
  if (npcs.length === 0) return {};
  return Object.fromEntries(npcs.map((participant) => [participant.uid, {
    profileVersion: NPC_PROFILE_VERSION,
    accuracyOffsetPermille: rotatedOffset(
      NPC_PROFILE_CONFIG.accuracyOffsetsPermille,
      matchId,
      participant.slot,
      "accuracy-profile"
    ),
    attemptOffsetPermille: rotatedOffset(
      NPC_PROFILE_CONFIG.attemptOffsetsPermille,
      matchId,
      participant.slot,
      "attempt-profile"
    ),
    reactionOffsetMs: rotatedOffset(
      NPC_PROFILE_CONFIG.reactionOffsetsMs,
      matchId,
      participant.slot,
      "reaction-profile"
    ),
  }]));
}

function isFastNPCQuestion({ matchId, slot, questionIndex }) {
  return deterministicInteger(matchId, slot, questionIndex, "fast-question")
    % NPC_PROFILE_CONFIG.fastQuestionModulo === 0;
}

function answerElapsedMs({
  matchId,
  slot,
  questionIndex,
  questionDurationMs,
  skillInput,
  profile,
  fastAnswer,
}) {
  const configuredNormal = skillInput?.normalAnswerElapsedMs;
  const configuredFast = skillInput?.fastAnswerElapsedMs;
  const remainingBased = Number.isFinite(skillInput?.answerRemainingMs)
    ? questionDurationMs - skillInput.answerRemainingMs
    : null;
  const fallback = Number.isFinite(skillInput?.reactionBaseMs)
    ? skillInput.reactionBaseMs
    : 250;
  const normalBase = Number.isFinite(configuredNormal)
    ? configuredNormal
    : (Number.isFinite(remainingBased) ? remainingBased : fallback);
  const fastBase = Number.isFinite(configuredFast) ? configuredFast : normalBase;
  const reactionOffset = Number.isFinite(profile?.reactionOffsetMs)
    ? profile.reactionOffsetMs
    : 0;
  const jitterRange = Number.isFinite(skillInput?.answerRemainingMs)
    ? NPC_PROFILE_CONFIG.remainingTargetQuestionJitterMs
    : NPC_PROFILE_CONFIG.questionJitterMs;
  const jitter = (deterministicInteger(matchId, slot, questionIndex, "timing-jitter")
    % (jitterRange * 2 + 1)) - jitterRange;
  const adjustedReactionOffset = fastAnswer
    ? Math.round(reactionOffset / 2)
    : reactionOffset;
  return clamp(
    (fastAnswer ? fastBase : normalBase) + adjustedReactionOffset + jitter,
    NPC_PROFILE_CONFIG.minimumAnswerElapsedMs,
    Math.max(
      NPC_PROFILE_CONFIG.minimumAnswerElapsedMs,
      questionDurationMs - NPC_PROFILE_CONFIG.deadlineSafetyMs
    )
  );
}

function createNPCAnswerPlan({
  matchId,
  participant,
  questionIndex,
  question,
  skillInput,
  profile,
}) {
  const configuredAccuracy = skillInput?.accuracyPermille;
  let answerId;
  if (Number.isFinite(configuredAccuracy)) {
    const attemptPermille = clamp(
      (skillInput.attemptPermille ?? 920) + (profile?.attemptOffsetPermille ?? 0),
      0,
      1_000
    );
    const accuracyPermille = clamp(
      configuredAccuracy + (profile?.accuracyOffsetPermille ?? 0),
      0,
      attemptPermille
    );
    const outcomeRoll = deterministicInteger(
      matchId,
      participant.slot,
      questionIndex,
      "answer-outcome"
    ) % 1_000;
    if (outcomeRoll >= attemptPermille) return null;
    answerId = outcomeRoll < accuracyPermille
      ? question.correctAnswerId
      : question.choices.find((choice) => choice.answerId !== question.correctAnswerId).answerId;
  } else {
    // Phase Cの固定test inputとの後方互換。
    const behavior = (questionIndex + participant.slot) % 3;
    if (behavior === 2) return null;
    answerId = behavior === 0
      ? question.correctAnswerId
      : question.choices.find((choice) => choice.answerId !== question.correctAnswerId).answerId;
  }

  const fastAnswer = isFastNPCQuestion({
    matchId,
    slot: participant.slot,
    questionIndex,
    profile,
  });
  const questionDurationMs = question.deadlineEpochMs - question.openedAtEpochMs;
  const elapsedMs = answerElapsedMs({
    matchId,
    slot: participant.slot,
    questionIndex,
    questionDurationMs,
    skillInput,
    profile,
    fastAnswer,
  });
  return {
    uid: participant.uid,
    eventId: `npc-answer-${question.questionId}-${participant.uid}`,
    questionId: question.questionId,
    answerId,
    acceptedAtEpochMs: question.openedAtEpochMs + elapsedMs,
    status: "ACCEPTED",
    source: "SERVER_NPC",
    npcProfileVersion: profile?.profileVersion || null,
    fastAnswer,
  };
}

module.exports = {
  NPC_PROFILE_CONFIG,
  NPC_PROFILE_VERSION,
  answerElapsedMs,
  buildNPCProfiles,
  createNPCAnswerPlan,
  deterministicInteger,
  isFastNPCQuestion,
};
