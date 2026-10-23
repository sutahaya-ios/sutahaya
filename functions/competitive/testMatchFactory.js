const { buildCompetitiveMatch } = require("./matchFactory");

function buildTestMatch(options) {
  return buildCompetitiveMatch({
    countdownDurationMs: 10,
    questionDurationMs: 5_000,
    resultDurationMs: 10,
    ...options,
  });
}

module.exports = { buildTestMatch };
