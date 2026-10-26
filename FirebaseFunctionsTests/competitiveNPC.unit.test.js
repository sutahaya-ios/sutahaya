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
    assert.ok(profiles.filter((profile) => profile.fastType).length <= 1);
  });

  it("selects about one fast-NPC match in three and never more than one NPC", () => {
    let fastMatches = 0;
    for (let index = 0; index < 300; index += 1) {
      const profiles = Object.values(buildNPCProfiles({
        matchId: `distribution-match-${index}`,
        participants,
      }));
      const fastCount = profiles.filter((profile) => profile.fastType).length;
      assert.ok(fastCount <= 1);
      if (fastCount === 1) fastMatches += 1;
    }
    assert.ok(fastMatches >= 80 && fastMatches <= 120, `fast matches: ${fastMatches}`);
  });

  it("selects about one fast question in five with retry-stable decisions", () => {
    let fastQuestions = 0;
    let totalQuestions = 0;
    for (let matchIndex = 0; matchIndex < 300; matchIndex += 1) {
      const matchId = `question-distribution-${matchIndex}`;
      const profiles = buildNPCProfiles({ matchId, participants });
      const fastEntry = Object.entries(profiles).find(([, profile]) => profile.fastType);
      if (!fastEntry) continue;
      const participant = participants.find((value) => value.uid === fastEntry[0]);
      for (let questionIndex = 0; questionIndex < 20; questionIndex += 1) {
        const input = {
          matchId,
          slot: participant.slot,
          questionIndex,
          profile: fastEntry[1],
        };
        const selected = isFastNPCQuestion(input);
        assert.equal(isFastNPCQuestion(input), selected);
        if (selected) fastQuestions += 1;
        totalQuestions += 1;
      }
    }
    const rate = fastQuestions / totalQuestions;
    assert.ok(rate >= 0.17 && rate <= 0.23, `fast question rate: ${rate}`);
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
            assert.ok(bronzeNormal >= 4_500 && bronzeNormal <= 5_500);
            assert.ok(bronzeFast >= 2_700 && bronzeFast <= 3_300);

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
