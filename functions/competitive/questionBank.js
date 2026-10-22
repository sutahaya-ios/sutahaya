const { createHash } = require("node:crypto");
const { QUESTION_COUNT } = require("./constants");
const ENGLISH_QUESTION_BANK = require("./data/englishQuestions.json");

const DISTRACTOR_STRIDE = 11;
const MINOR_FUNCTION_WORDS = new Set(["代名詞", "接続詞", "前置詞", "助動詞"]);

function distractorGroup(question) {
  return MINOR_FUNCTION_WORDS.has(question.pos) ? "MINOR_FUNCTION_WORDS" : question.pos;
}

function meaningElements(meaning) {
  const elements = new Set();
  let current = "";
  let depth = 0;
  for (const character of meaning) {
    if (["（", "("].includes(character)) {
      depth += 1;
      current += character;
    } else if (["）", ")"].includes(character)) {
      depth = Math.max(0, depth - 1);
      current += character;
    } else if (["、", "・"].includes(character) && depth === 0) {
      if (current) elements.add(current);
      current = "";
    } else if (![" ", "　"].includes(character)) {
      current += character;
    }
  }
  if (current) elements.add(current);
  return elements;
}

function disjoint(left, right) {
  return [...left].every((value) => !right.has(value));
}

const groups = Object.fromEntries(Object.entries(Object.groupBy(
  ENGLISH_QUESTION_BANK,
  distractorGroup
)));

function distractorsFor(question) {
  const group = groups[distractorGroup(question)] || [];
  const base = group.findIndex((candidate) => candidate.id === question.id);
  const correctElements = meaningElements(question.meaning);
  const result = [];
  for (let step = 1; step < group.length && result.length < 3; step += 1) {
    const candidate = group[(base + step * DISTRACTOR_STRIDE) % group.length].meaning;
    if (candidate !== question.meaning
        && disjoint(correctElements, meaningElements(candidate))
        && !result.includes(candidate)) {
      result.push(candidate);
    }
  }
  if (result.length !== 3) {
    throw new Error(`Competitive question ${question.id} has insufficient distractors`);
  }
  return result;
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

function selectCompetitiveQuestions({ matchId, difficultyBand }) {
  const minimum = difficultyBand?.minimum;
  const maximum = difficultyBand?.maximum;
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum)
      || minimum < 1 || maximum > 5 || minimum > maximum) {
    throw new Error("Competitive difficulty band must be within 1...5");
  }
  const eligible = ENGLISH_QUESTION_BANK
    .filter((question) => question.difficulty >= minimum && question.difficulty <= maximum)
    .sort((left, right) => digest(`${matchId}:${left.id}`)
      .localeCompare(digest(`${matchId}:${right.id}`)));
  if (eligible.length < QUESTION_COUNT) {
    throw new Error(`Only ${eligible.length} Competitive questions are eligible`);
  }
  return eligible.slice(0, QUESTION_COUNT).map((question) => {
    const choices = [question.meaning, ...distractorsFor(question)]
      .sort((left, right) => digest(`${matchId}:${question.id}:${left}`)
        .localeCompare(digest(`${matchId}:${question.id}:${right}`)));
    return {
      canonicalId: question.id,
      difficulty: question.difficulty,
      prompt: question.word,
      choices,
      correctChoiceIndex: choices.indexOf(question.meaning),
    };
  });
}

module.exports = {
  ENGLISH_QUESTION_BANK,
  selectCompetitiveQuestions,
};
