const fs = require("node:fs");
const path = require("node:path");

const rootDir = path.resolve(__dirname, "..");
const sourceFiles = ["junior_high", "high_school", "toeic"];
const outputPath = path.join(
  rootDir,
  "functions",
  "competitive",
  "data",
  "englishQuestions.json"
);
const requiredRanges = Object.freeze({
  BRONZE: [1, 2],
  SILVER: [2, 3],
  GOLD: [3, 4],
  PLATINUM: [4, 5],
  RATING_BATTLE: [5, 5],
});

function loadSourceQuestions() {
  const questions = sourceFiles.flatMap((name) => {
    const sourcePath = path.join(rootDir, "HayaosiApp", "Resources", `${name}.json`);
    const entries = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
    return entries.map(({ id, word, meaning, pos, difficulty }) => ({
      id,
      word,
      meaning,
      pos,
      difficulty,
    }));
  });

  const ids = new Set();
  for (const question of questions) {
    if (typeof question.id !== "string" || !question.id
        || typeof question.word !== "string" || !question.word
        || typeof question.meaning !== "string" || !question.meaning
        || typeof question.pos !== "string" || !question.pos
        || !Number.isInteger(question.difficulty)
        || question.difficulty < 1
        || question.difficulty > 5) {
      throw new Error(`Invalid English question source entry: ${question.id || "unknown"}`);
    }
    if (ids.has(question.id)) throw new Error(`Duplicate English question id: ${question.id}`);
    ids.add(question.id);
  }
  return questions;
}

function countsFor(questions) {
  const difficulties = Object.fromEntries([1, 2, 3, 4, 5].map((difficulty) => [
    difficulty,
    questions.filter((question) => question.difficulty === difficulty).length,
  ]));
  const ranges = Object.fromEntries(Object.entries(requiredRanges).map(([tier, [minimum, maximum]]) => [
    tier,
    questions.filter((question) => (
      question.difficulty >= minimum && question.difficulty <= maximum
    )).length,
  ]));
  return { difficulties, ranges };
}

const questions = loadSourceQuestions();
const counts = countsFor(questions);
for (const [tier, count] of Object.entries(counts.ranges)) {
  if (count < 20) throw new Error(`${tier} has only ${count} eligible questions`);
}

const serialized = `${JSON.stringify(questions)}\n`;
if (process.argv.includes("--check")) {
  if (!fs.existsSync(outputPath) || fs.readFileSync(outputPath, "utf8") !== serialized) {
    throw new Error("Competitive question bank is not synchronized; run with --write");
  }
} else if (process.argv.includes("--write")) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, serialized);
} else {
  throw new Error("Use --check or --write");
}

process.stdout.write(`${JSON.stringify({ total: questions.length, ...counts })}\n`);
