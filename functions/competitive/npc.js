const { createHash } = require("node:crypto");

const {
  NPC_STRENGTH_PROFILE_VERSION,
  attemptPermille,
  nearestNPCStrengthProfile,
  npcStrengthProfile,
} = require("./npcStrengthProfiles");

const NPC_PROFILE_VERSION = "competitive-npc-profile-v3";
const NPC_PROFILE_CONFIG = Object.freeze({
  minimumAnswerElapsedMs: 1_200,
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

function deterministicUnit(...parts) {
  return deterministicInteger(...parts) / 0x100000000;
}

function npcParticipants(participants) {
  const values = Array.isArray(participants) ? participants : Object.values(participants || {});
  return values
    .filter((participant) => participant.kind === "NPC")
    .sort((left, right) => left.slot - right.slot || left.uid.localeCompare(right.uid));
}

function resolvedStrengthProfile(skillInput, profile = null) {
  const profileId = profile?.strengthProfileId || skillInput?.strengthProfileId;
  const exact = npcStrengthProfile(profileId);
  if (exact) return exact;

  // deploy境界で旧matchを壊さないため、旧private configは最も近い既存7体へ丸める。
  return nearestNPCStrengthProfile(
    Number.isFinite(skillInput?.accuracyPermille) ? skillInput.accuracyPermille : 500
  );
}

function privateNPCProfile(strength) {
  return {
    profileVersion: NPC_PROFILE_VERSION,
    strengthProfileVersion: NPC_STRENGTH_PROFILE_VERSION,
    strengthProfileId: strength.id,
    strengthProfileName: strength.name,
    sourceNPCId: strength.sourceNPCId,
    sourceNickname: strength.sourceNickname,
    accuracyPermille: strength.accuracyPermille,
    remainingRatio: strength.remainingRatio,
    unansweredDenominator: strength.unansweredDenominator,
    attemptPermille: attemptPermille(strength),
  };
}

function buildNPCProfiles({ matchId, participants, skillInput }) {
  const npcs = npcParticipants(participants);
  if (npcs.length === 0) return {};
  const strength = resolvedStrengthProfile(skillInput);
  return Object.fromEntries(npcs.map((participant) => [
    participant.uid,
    privateNPCProfile(strength),
  ]));
}

function answerElapsedMs({
  matchId,
  slot,
  questionIndex,
  questionDurationMs,
  profile,
  skillInput,
}) {
  const strength = resolvedStrengthProfile(skillInput, profile);
  const earliest = NPC_PROFILE_CONFIG.minimumAnswerElapsedMs;
  const latest = questionDurationMs - NPC_PROFILE_CONFIG.deadlineSafetyMs;
  if (latest < earliest) return null;

  const target = clamp(
    questionDurationMs * (1 - strength.remainingRatio),
    earliest,
    latest
  );
  const jitterLimit = Math.max(0, Math.min(target - earliest, latest - target));
  // 2つの独立uniform値の和で、平均付近が出やすく両端も残る三角分布にする。
  const triangular = deterministicUnit(matchId, slot, questionIndex, "timing-a")
    + deterministicUnit(matchId, slot, questionIndex, "timing-b") - 1;
  return Math.round(clamp(target + triangular * jitterLimit, earliest, latest));
}

function shouldNPCAnswer({ matchId, slot, questionIndex, profile, skillInput }) {
  const strength = resolvedStrengthProfile(skillInput, profile);
  return deterministicInteger(matchId, slot, questionIndex, "answer-attempt")
    % strength.unansweredDenominator !== 0;
}

function shouldNPCAnswerCorrectly({ matchId, slot, questionIndex, profile, skillInput }) {
  const strength = resolvedStrengthProfile(skillInput, profile);
  return deterministicInteger(matchId, slot, questionIndex, "answer-correctness")
    % 1_000 < strength.accuracyPermille;
}

function createNPCAnswerPlan({
  matchId,
  participant,
  questionIndex,
  question,
  skillInput,
  profile,
}) {
  if (!shouldNPCAnswer({
    matchId,
    slot: participant.slot,
    questionIndex,
    profile,
    skillInput,
  })) return null;

  const questionDurationMs = question.deadlineEpochMs - question.openedAtEpochMs;
  const elapsedMs = answerElapsedMs({
    matchId,
    slot: participant.slot,
    questionIndex,
    questionDurationMs,
    profile,
    skillInput,
  });
  if (!Number.isFinite(elapsedMs)) return null;

  const isCorrect = shouldNPCAnswerCorrectly({
    matchId,
    slot: participant.slot,
    questionIndex,
    profile,
    skillInput,
  });
  const wrongs = question.choices.filter(
    (choice) => choice.answerId !== question.correctAnswerId
  );
  const wrongIndex = wrongs.length === 0
    ? 0
    : deterministicInteger(matchId, participant.slot, questionIndex, "wrong-choice")
      % wrongs.length;
  const answerId = isCorrect || wrongs.length === 0
    ? question.correctAnswerId
    : wrongs[wrongIndex].answerId;
  const strength = resolvedStrengthProfile(skillInput, profile);

  return {
    uid: participant.uid,
    eventId: `npc-answer-${question.questionId}-${participant.uid}`,
    questionId: question.questionId,
    answerId,
    acceptedAtEpochMs: question.openedAtEpochMs + elapsedMs,
    status: "ACCEPTED",
    source: "SERVER_NPC",
    npcProfileVersion: profile?.profileVersion || NPC_PROFILE_VERSION,
    strengthProfileId: strength.id,
  };
}

module.exports = {
  NPC_PROFILE_CONFIG,
  NPC_PROFILE_VERSION,
  answerElapsedMs,
  buildNPCProfiles,
  createNPCAnswerPlan,
  deterministicInteger,
  resolvedStrengthProfile,
  shouldNPCAnswer,
  shouldNPCAnswerCorrectly,
};
