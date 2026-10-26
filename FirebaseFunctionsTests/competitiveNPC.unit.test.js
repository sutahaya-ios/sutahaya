const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  answerElapsedMs,
  buildNPCProfiles,
  createNPCAnswerPlan,
  isFastNPCQuestion,
} = require("../functions/competitive/npc");
const { npcSkillInputForRating } = require("../functions/competitive/rating");

const participants = [
  { uid: "human", slot: 0, kind: "HUMAN" },
  { uid: "npc-1", slot: 1, kind: "NPC" },
  { uid: "npc-2", slot: 2, kind: "NPC" },
  { uid: "npc-3", slot: 3, kind: "NPC" },
];

function question(openedAtEpochMs = 10_000, durationMs = 8_000) {
  return {
    questionId: "question-1",
    correctAnswerId: "correct",
    choices: [{ answerId: "correct" }, { answerId: "wrong" }],
    openedAtEpochMs,
    deadlineEpochMs: openedAtEpochMs + durationMs,
  };
}

describe("Competitive NPC profile", () => {
  it("keeps one deterministic profile per match and gives different slots small offsets", () => {
    const first = buildNPCProfiles({ matchId: "profile-match", participants });
    const retry = buildNPCProfiles({ matchId: "profile-match", participants });
    assert.deepEqual(retry, first);

    const profiles = Object.values(first);
    assert.equal(profiles.length, 3);
    assert.equal(new Set(profiles.map((profile) => profile.accuracyOffsetPermille)).size, 3);
    assert.equal(new Set(profiles.map((profile) => profile.reactionOffsetMs)).size, 3);
    assert.ok(profiles.every((profile) => Math.abs(profile.accuracyOffsetPermille) <= 30));
    assert.ok(profiles.every((profile) => Math.abs(profile.reactionOffsetMs) <= 300));
    assert.ok(profiles.every((profile) => !("fastType" in profile)));
  });

  it("gives every NPC a low, retry-stable chance of answering early", () => {
    let fastQuestions = 0;
    let totalQuestions = 0;
    const fastQuestionsBySlot = new Map();
    for (let matchIndex = 0; matchIndex < 300; matchIndex += 1) {
      const matchId = `question-distribution-${matchIndex}`;
      for (const participant of participants.filter((value) => value.kind === "NPC")) {
        for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
          const input = {
            matchId,
            slot: participant.slot,
            questionIndex,
          };
          const selected = isFastNPCQuestion(input);
          assert.equal(isFastNPCQuestion(input), selected);
          if (selected) {
            fastQuestions += 1;
            fastQuestionsBySlot.set(
              participant.slot,
              (fastQuestionsBySlot.get(participant.slot) || 0) + 1
            );
          }
          totalQuestions += 1;
        }
      }
    }
    const rate = fastQuestions / totalQuestions;
    assert.ok(rate >= 0.018 && rate <= 0.027, `fast question rate: ${rate}`);
    assert.ok(
      participants.filter((value) => value.kind === "NPC")
        .every((participant) => (fastQuestionsBySlot.get(participant.slot) || 0) > 0)
    );
  });

  it("keeps Bronze and Silver normal/fast timing within human-like ranges", () => {
    const bronzeSkills = [1_000, 1_199].map((rating) => npcSkillInputForRating(rating));
    const silverSkills = [1_200, 1_399].map((rating) => npcSkillInputForRating(rating));
    for (const bronze of bronzeSkills) {
      for (const silver of silverSkills) {
        for (const reactionOffsetMs of [-300, -100, 100, 300]) {
          for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
            const common = {
              matchId: "timing-range",
              slot: 2,
              questionIndex,
              profile: { reactionOffsetMs },
            };
            const bronzeNormal = answerElapsedMs({
              ...common,
              questionDurationMs: 8_000,
              skillInput: bronze,
              fastAnswer: false,
            });
            const bronzeFast = answerElapsedMs({
              ...common,
              questionDurationMs: 8_000,
              skillInput: bronze,
              fastAnswer: true,
            });
            assert.ok(bronzeNormal >= 4_200 && bronzeNormal <= 5_800);
            assert.ok(bronzeFast >= 2_300 && bronzeFast <= 3_700);

            const silverNormal = answerElapsedMs({
              ...common,
              questionDurationMs: 5_000,
              skillInput: silver,
              fastAnswer: false,
            });
            const silverFast = answerElapsedMs({
              ...common,
              questionDurationMs: 5_000,
              skillInput: silver,
              fastAnswer: true,
            });
            assert.ok(silverNormal >= 3_500 && silverNormal <= 4_800);
            assert.ok(silverFast >= 2_000);
            assert.ok(silverNormal - silverFast >= 1_000);
            assert.ok(silverNormal - silverFast <= 2_000);
          }
        }
      }
    }
  });

  it("keeps speed independent from correctness and retains wrong/unanswered cases", () => {
    const skillInput = npcSkillInputForRating(1_000);
    let fastWrong = null;
    let unansweredFound = false;
    for (let matchIndex = 0; matchIndex < 500 && (!fastWrong || !unansweredFound); matchIndex += 1) {
      const matchId = `outcome-match-${matchIndex}`;
      const profiles = buildNPCProfiles({ matchId, participants });
      for (const participant of participants.filter((value) => value.kind === "NPC")) {
        const profile = profiles[participant.uid];
        for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
          const input = {
            matchId,
            participant,
            questionIndex,
            question: question(),
            skillInput,
            profile,
          };
          const first = createNPCAnswerPlan(input);
          const retry = createNPCAnswerPlan(input);
          assert.deepEqual(retry, first);
          if (!first) {
            unansweredFound = true;
          } else if (first.fastAnswer && first.answerId === "wrong") {
            fastWrong = first;
          }
        }
      }
    }
    assert.ok(fastWrong, "a fast wrong answer should exist");
    assert.equal(fastWrong.fastAnswer, true);
    assert.equal(fastWrong.answerId, "wrong");
    assert.equal(unansweredFound, true);
  });
});
