const NPC_STRENGTH_PROFILE_VERSION = "shared-seven-npc-v1";

// Friend BattleのCPUProfile.rosterが持つ既存accuracyを昇順に並べたmirror。
// Firebase FunctionsからSwiftを直接importできないため、unit testでSwift原本との一致を固定する。
const NPC_STRENGTH_PROFILES = Object.freeze([
  Object.freeze({
    id: "VERY_WEAK",
    name: "超弱",
    sourceNPCId: "cpu-weak",
    sourceNickname: "CPU(弱)",
    accuracyPermille: 350,
    remainingRatio: 0.15,
    unansweredDenominator: 3,
  }),
  Object.freeze({
    id: "WEAK",
    name: "弱",
    sourceNPCId: "cpu-c",
    sourceNickname: "CPU(C)",
    accuracyPermille: 400,
    remainingRatio: 0.25,
    unansweredDenominator: 5,
  }),
  Object.freeze({
    id: "SLIGHTLY_WEAK",
    name: "ちょい弱",
    sourceNPCId: "cpu-a",
    sourceNickname: "CPU(A)",
    accuracyPermille: 450,
    remainingRatio: 0.35,
    unansweredDenominator: 8,
  }),
  Object.freeze({
    id: "NORMAL",
    name: "普通",
    sourceNPCId: "cpu-b",
    sourceNickname: "CPU(B)",
    accuracyPermille: 500,
    remainingRatio: 0.50,
    unansweredDenominator: 15,
  }),
  Object.freeze({
    id: "SLIGHTLY_STRONG",
    name: "ちょい強",
    sourceNPCId: "cpu-normal",
    sourceNickname: "CPU(中)",
    accuracyPermille: 550,
    remainingRatio: 0.55,
    unansweredDenominator: 20,
  }),
  Object.freeze({
    id: "STRONG",
    name: "強",
    sourceNPCId: "cpu-d",
    sourceNickname: "CPU(D)",
    accuracyPermille: 600,
    remainingRatio: 0.60,
    unansweredDenominator: 25,
  }),
  Object.freeze({
    id: "VERY_STRONG",
    name: "鬼強",
    sourceNPCId: "cpu-strong",
    sourceNickname: "CPU(強)",
    accuracyPermille: 750,
    remainingRatio: 0.70,
    unansweredDenominator: 30,
  }),
]);

function npcStrengthProfile(profileId) {
  return NPC_STRENGTH_PROFILES.find((profile) => profile.id === profileId) || null;
}

function nearestNPCStrengthProfile(targetAccuracyPermille) {
  const target = Number.isFinite(targetAccuracyPermille) ? targetAccuracyPermille : 500;
  return NPC_STRENGTH_PROFILES.reduce((nearest, profile) => {
    const distance = Math.abs(profile.accuracyPermille - target);
    const nearestDistance = Math.abs(nearest.accuracyPermille - target);
    return distance < nearestDistance ? profile : nearest;
  });
}

function attemptPermille(profile) {
  return Math.round(1_000 * (1 - 1 / profile.unansweredDenominator));
}

module.exports = {
  NPC_STRENGTH_PROFILES,
  NPC_STRENGTH_PROFILE_VERSION,
  attemptPermille,
  nearestNPCStrengthProfile,
  npcStrengthProfile,
};
