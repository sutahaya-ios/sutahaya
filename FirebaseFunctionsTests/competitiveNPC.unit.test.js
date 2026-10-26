const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { describe, it } = require("node:test");

const {
  NPC_PROFILE_CONFIG,
  answerElapsedMs,
  buildNPCProfiles,
  createNPCAnswerPlan,
} = require("../functions/competitive/npc");
const {
  NPC_STRENGTH_PROFILES,
  attemptPermille,
} = require("../functions/competitive/npcStrengthProfiles");
const { npcSkillInputForRating } = require("../functions/competitive/rating");

const participant = { uid: "npc-1", slot: 1, kind: "NPC" };
const participants = [
  { uid: "human", slot: 0, kind: "HUMAN" },
  participant,
  { uid: "npc-2", slot: 2, kind: "NPC" },
  { uid: "npc-3", slot: 3, kind: "NPC" },
];

function question(questionIndex = 0, openedAtEpochMs = 10_000, durationMs = 8_000) {
  return {
    questionId: `question-${questionIndex}`,
    correctAnswerId: "correct",
    choices: [
      { answerId: "correct" },
      { answerId: "wrong-1" },
      { answerId: "wrong-2" },
    ],
    openedAtEpochMs,
    deadlineEpochMs: openedAtEpochMs + durationMs,
  };
}

function skillInput(profile) {
  return {
    strengthProfileId: profile.id,
    accuracyPermille: profile.accuracyPermille,
  };
}

function simulate(profile, sampleCount = 10_000) {
  let answered = 0;
  let correct = 0;
  let remainingRatioTotal = 0;
  let minimumElapsedMs = Number.POSITIVE_INFINITY;
  let maximumElapsedMs = Number.NEGATIVE_INFINITY;
  const unansweredIndexes = [];

  for (let questionIndex = 0; questionIndex < sampleCount; questionIndex += 1) {
    const plan = createNPCAnswerPlan({
      matchId: "npc-strength-simulation",
      participant,
      questionIndex,
      question: question(questionIndex),
      skillInput: skillInput(profile),
      profile: { strengthProfileId: profile.id },
    });
    if (!plan) {
      unansweredIndexes.push(questionIndex);
      continue;
    }
    answered += 1;
    if (plan.answerId === "correct") correct += 1;
    const elapsedMs = plan.acceptedAtEpochMs - 10_000;
    minimumElapsedMs = Math.min(minimumElapsedMs, elapsedMs);
    maximumElapsedMs = Math.max(maximumElapsedMs, elapsedMs);
    remainingRatioTotal += (8_000 - elapsedMs) / 8_000;
  }

  return {
    answered,
    unanswered: sampleCount - answered,
    unansweredRate: (sampleCount - answered) / sampleCount,
    accuracy: correct / answered,
    meanRemainingRatio: remainingRatioTotal / answered,
    minimumElapsedMs,
    maximumElapsedMs,
    unansweredIndexes,
  };
}

describe("Competitive NPC strength profiles", () => {
  it("maps the existing seven Friend Battle NPC accuracies in ascending order", () => {
    assert.deepEqual(
      NPC_STRENGTH_PROFILES.map((profile) => ({
        name: profile.name,
        sourceNPCId: profile.sourceNPCId,
        accuracyPermille: profile.accuracyPermille,
        remainingRatio: profile.remainingRatio,
        unansweredDenominator: profile.unansweredDenominator,
      })),
      [
        { name: "超弱", sourceNPCId: "cpu-weak", accuracyPermille: 350, remainingRatio: 0.15, unansweredDenominator: 3 },
        { name: "弱", sourceNPCId: "cpu-c", accuracyPermille: 400, remainingRatio: 0.25, unansweredDenominator: 5 },
        { name: "ちょい弱", sourceNPCId: "cpu-a", accuracyPermille: 450, remainingRatio: 0.35, unansweredDenominator: 8 },
        { name: "普通", sourceNPCId: "cpu-b", accuracyPermille: 500, remainingRatio: 0.50, unansweredDenominator: 15 },
        { name: "ちょい強", sourceNPCId: "cpu-normal", accuracyPermille: 550, remainingRatio: 0.55, unansweredDenominator: 20 },
        { name: "強", sourceNPCId: "cpu-d", accuracyPermille: 600, remainingRatio: 0.60, unansweredDenominator: 25 },
        { name: "鬼強", sourceNPCId: "cpu-strong", accuracyPermille: 750, remainingRatio: 0.70, unansweredDenominator: 30 },
      ]
    );
  });

  it("keeps the Backend mirror equal to the Swift Friend Battle source", () => {
    const swift = readFileSync(join(
      __dirname,
      "../HayaosiApp/Services/Battle/CPUAnswerStrategy.swift"
    ), "utf8");
    const swiftStrengthCases = {
      VERY_WEAK: "veryWeak",
      WEAK: "weak",
      SLIGHTLY_WEAK: "slightlyWeak",
      NORMAL: "normal",
      SLIGHTLY_STRONG: "slightlyStrong",
      STRONG: "strong",
      VERY_STRONG: "veryStrong",
    };
    for (const profile of NPC_STRENGTH_PROFILES) {
      const accuracy = (profile.accuracyPermille / 1_000).toFixed(2);
      const nickname = profile.sourceNickname.replace(/[()]/g, "\\$&");
      const pattern = new RegExp(
        `CPUProfile\\(id: "${profile.sourceNPCId}", nickname: "${nickname}", strength: \\.${swiftStrengthCases[profile.id]},\\s+correctProbability: ${accuracy}\\)`
      );
      assert.match(swift, pattern, `${profile.name} must match the Swift source`);
    }
  });

  it("stores only one of the seven profiles and is retry stable", () => {
    const input = npcSkillInputForRating(1_000);
    const first = buildNPCProfiles({ matchId: "profile-match", participants, skillInput: input });
    const retry = buildNPCProfiles({ matchId: "profile-match", participants, skillInput: input });
    assert.deepEqual(retry, first);
    assert.equal(Object.keys(first).length, 3);
    assert.ok(Object.values(first).every((profile) => (
      profile.strengthProfileId === input.strengthProfileId
      && NPC_STRENGTH_PROFILES.some((candidate) => (
        candidate.accuracyPermille === profile.accuracyPermille
      ))
    )));
  });

  it("converges accuracy, unanswered rate, and mean timing for all seven profiles", () => {
    for (const profile of NPC_STRENGTH_PROFILES) {
      const result = simulate(profile);
      assert.ok(
        Math.abs(result.accuracy - profile.accuracyPermille / 1_000) <= 0.02,
        `${profile.name} accuracy=${result.accuracy}`
      );
      assert.ok(
        Math.abs(result.unansweredRate - 1 / profile.unansweredDenominator) <= 0.015,
        `${profile.name} unanswered=${result.unansweredRate}`
      );
      assert.ok(
        Math.abs(result.meanRemainingRatio - profile.remainingRatio) <= 0.015,
        `${profile.name} remaining=${result.meanRemainingRatio}`
      );
      assert.ok(result.minimumElapsedMs >= NPC_PROFILE_CONFIG.minimumAnswerElapsedMs);
      assert.ok(result.maximumElapsedMs <= 7_900);
      assert.ok(
        result.maximumElapsedMs - result.minimumElapsedMs >= 500,
        `${profile.name} timing must have visible variance`
      );
      const gaps = result.unansweredIndexes.slice(1).map((value, index) => (
        value - result.unansweredIndexes[index]
      ));
      assert.ok(new Set(gaps).size > 3, `${profile.name} unanswered must not use a fixed cycle`);
    }
  });

  it("keeps attempt, correctness, and timing independent and deterministic", () => {
    let veryWeakCorrect = null;
    let veryStrongWrong = null;
    let unanswered = null;
    const weak = NPC_STRENGTH_PROFILES[0];
    const strong = NPC_STRENGTH_PROFILES.at(-1);
    for (let questionIndex = 0; questionIndex < 2_000; questionIndex += 1) {
      for (const [profile, capture] of [
        [weak, (plan) => { if (plan?.answerId === "correct") veryWeakCorrect ||= plan; }],
        [strong, (plan) => { if (plan && plan.answerId !== "correct") veryStrongWrong ||= plan; }],
      ]) {
        const input = {
          matchId: "independence-match",
          participant,
          questionIndex,
          question: question(questionIndex),
          skillInput: skillInput(profile),
          profile: { strengthProfileId: profile.id },
        };
        const first = createNPCAnswerPlan(input);
        assert.deepEqual(createNPCAnswerPlan(input), first);
        capture(first);
        if (!first) unanswered ||= { profile: profile.id, questionIndex };
      }
    }
    assert.ok(veryWeakCorrect, "very weak NPC can answer correctly");
    assert.ok(veryStrongWrong, "very strong NPC can answer incorrectly");
    assert.ok(unanswered, "answer participation is a separate decision");
    assert.notEqual(veryWeakCorrect.acceptedAtEpochMs, veryStrongWrong.acceptedAtEpochMs);
  });

  it("varies timing by question while keeping the same seed stable", () => {
    const profile = NPC_STRENGTH_PROFILES[3];
    const values = Array.from({ length: 30 }, (_, questionIndex) => answerElapsedMs({
      matchId: "timing-seed",
      slot: 2,
      questionIndex,
      questionDurationMs: 8_000,
      skillInput: skillInput(profile),
      profile: { strengthProfileId: profile.id },
    }));
    assert.ok(new Set(values).size > 20);
    assert.equal(values[7], answerElapsedMs({
      matchId: "timing-seed",
      slot: 2,
      questionIndex: 7,
      questionDurationMs: 8_000,
      skillInput: skillInput(profile),
      profile: { strengthProfileId: profile.id },
    }));
  });

  it("does not schedule an answer when the deadline cannot honor the 1.2 second floor", () => {
    const profile = NPC_STRENGTH_PROFILES.at(-1);
    const plan = createNPCAnswerPlan({
      matchId: "short-question",
      participant,
      questionIndex: 0,
      question: question(0, 10_000, 1_200),
      skillInput: skillInput(profile),
      profile: { strengthProfileId: profile.id },
    });
    assert.equal(plan, null);
  });

  it("derives attempt probability from unanswered rate without changing accuracy", () => {
    for (const profile of NPC_STRENGTH_PROFILES) {
      assert.equal(
        attemptPermille(profile),
        Math.round(1_000 * (1 - 1 / profile.unansweredDenominator))
      );
    }
  });
});
