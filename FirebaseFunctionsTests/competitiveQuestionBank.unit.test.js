const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { QUESTION_COUNT } = require("../functions/competitive/constants");
const {
  RATING_CONFIG,
  TIER,
  questionSelectionBoundary,
} = require("../functions/competitive/rating");
const {
  ENGLISH_QUESTION_BANK,
  selectCompetitiveQuestions,
} = require("../functions/competitive/questionBank");

const EXPECTED_COUNTS = Object.freeze({
  1: 1_399,
  2: 1_353,
  3: 1_515,
  4: 878,
  5: 806,
});

const TIER_CASES = Object.freeze([
  { tier: TIER.BRONZE, rating: 1_000, minimum: 1, maximum: 2, count: 2_752 },
  { tier: TIER.SILVER, rating: 1_200, minimum: 2, maximum: 3, count: 2_868 },
  { tier: TIER.GOLD, rating: 1_400, minimum: 3, maximum: 4, count: 2_393 },
  { tier: TIER.PLATINUM, rating: 1_600, minimum: 4, maximum: 5, count: 1_684 },
  { tier: TIER.RATING_BATTLE, rating: 1_800, minimum: 5, maximum: 5, count: 806 },
]);

describe("Competitive Phase D-2 question bank", () => {
  it("contains the synchronized 1...5 English data and at least 20 per range", () => {
    assert.equal(ENGLISH_QUESTION_BANK.length, 5_951);
    assert.equal(new Set(ENGLISH_QUESTION_BANK.map((question) => question.id)).size, 5_951);
    for (const [difficulty, expectedCount] of Object.entries(EXPECTED_COUNTS)) {
      assert.equal(
        ENGLISH_QUESTION_BANK.filter((question) => question.difficulty === Number(difficulty)).length,
        expectedCount
      );
    }
    for (const testCase of TIER_CASES) {
      const count = ENGLISH_QUESTION_BANK.filter((question) => (
        question.difficulty >= testCase.minimum
        && question.difficulty <= testCase.maximum
      )).length;
      assert.equal(count, testCase.count);
      assert.ok(count >= QUESTION_COUNT);
    }
  });

  it("maps every match tier to its confirmed difficulty range", () => {
    for (const testCase of TIER_CASES) {
      const selection = questionSelectionBoundary(testCase.rating);
      assert.equal(selection.matchTier, testCase.tier);
      assert.deepEqual(selection.difficultyBand, {
        minimum: testCase.minimum,
        maximum: testCase.maximum,
      });
      assert.equal(selection.mappingStatus, "PRODUCT_MAPPING_CONFIRMED");
    }
  });

  it("selects 20 unique questions and four choices inside every tier range", () => {
    for (const testCase of TIER_CASES) {
      const selected = selectCompetitiveQuestions({
        matchId: `match-${testCase.tier}`,
        difficultyBand: RATING_CONFIG.difficultyRanges[testCase.tier],
      });
      assert.equal(selected.length, QUESTION_COUNT);
      assert.equal(new Set(selected.map((question) => question.canonicalId)).size, QUESTION_COUNT);
      assert.ok(selected.every((question) => (
        question.difficulty >= testCase.minimum
        && question.difficulty <= testCase.maximum
        && question.choices.length === 4
        && question.correctChoiceIndex >= 0
        && question.correctChoiceIndex < 4
      )));
    }
  });

  it("derives one mixed-tier range from human average MMR", () => {
    const humanRatings = [1_100, 1_500, 1_600];
    const average = humanRatings.reduce((sum, rating) => sum + rating, 0) / humanRatings.length;
    const selection = questionSelectionBoundary(average);
    assert.equal(selection.sourceAverageHiddenRating, 1_400);
    assert.equal(selection.matchTier, TIER.GOLD);
    assert.deepEqual(selection.difficultyBand, { minimum: 3, maximum: 4 });
  });
});
