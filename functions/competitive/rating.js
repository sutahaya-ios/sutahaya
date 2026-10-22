const RATING_CONFIG = Object.freeze({
  // Phase D-1の暫定値。Product調整はこのconfigだけで行う。
  configVersion: "competitive-rating-d1-provisional-1",
  formulaVersion: "pairwise-elo-average-v1",
  initialRating: 1_000,
  minimumRating: 0,
  kFactor: 32,
  eloScale: 400,
  tierThresholds: Object.freeze({
    SILVER: 1_100,
    GOLD: 1_250,
    PLATINUM: 1_400,
  }),
  ratingBattleThreshold: 1_600,
  seasonSoftResetFactor: 0.75,
  seasonDurationMs: 28 * 24 * 60 * 60 * 1_000,
  seasonEpochStartMs: Date.UTC(2026, 0, 5),
  seasonSettlementVersion: "competitive-season-d1-1",
  npcSkill: Object.freeze({
    attemptPermille: 920,
    accuracyBasePermille: 620,
    accuracySlopePerRatingPoint: 0.35,
    minimumAccuracyPermille: 350,
    maximumAccuracyPermille: 900,
    reactionBaseMs: 700,
    reactionSlopePerRatingPoint: 0.45,
    minimumReactionMs: 180,
    maximumReactionMs: 1_100,
  }),
});

const TIER = Object.freeze({
  BRONZE: "BRONZE",
  SILVER: "SILVER",
  GOLD: "GOLD",
  PLATINUM: "PLATINUM",
  RATING_BATTLE: "RATING_BATTLE",
});

function clamp(value, lower, upper) {
  return Math.min(upper, Math.max(lower, value));
}

function tierForRating(rating, config = RATING_CONFIG) {
  if (rating >= config.ratingBattleThreshold) return TIER.RATING_BATTLE;
  if (rating >= config.tierThresholds.PLATINUM) return TIER.PLATINUM;
  if (rating >= config.tierThresholds.GOLD) return TIER.GOLD;
  if (rating >= config.tierThresholds.SILVER) return TIER.SILVER;
  return TIER.BRONZE;
}

function seasonForEpoch(nowEpochMs, config = RATING_CONFIG) {
  const seasonIndex = Math.max(
    0,
    Math.floor((nowEpochMs - config.seasonEpochStartMs) / config.seasonDurationMs)
  );
  const startsAtEpochMs = config.seasonEpochStartMs
    + seasonIndex * config.seasonDurationMs;
  return {
    seasonId: `season-${seasonIndex + 1}`,
    startsAtEpochMs,
    endsAtEpochMs: startsAtEpochMs + config.seasonDurationMs,
  };
}

function softResetRating(rating, config = RATING_CONFIG) {
  return Math.max(
    config.minimumRating,
    Math.round(
      config.initialRating
      + (rating - config.initialRating) * config.seasonSoftResetFactor
    )
  );
}

function initialCompetitiveProfile(nowEpochMs, config = RATING_CONFIG) {
  const season = seasonForEpoch(nowEpochMs, config);
  return {
    hiddenRating: config.initialRating,
    currentTier: tierForRating(config.initialRating, config),
    ratingBattle: false,
    stats: {
      matchesPlayed: 0,
      totalWins: 0,
      currentWinStreak: 0,
      maxWinStreak: 0,
    },
    season: {
      ...season,
      ratingAtSeasonStart: config.initialRating,
      previousSeasonEndRating: null,
      settlementVersion: config.seasonSettlementVersion,
    },
    ratingConfigVersion: config.configVersion,
    updatedAtEpochMs: nowEpochMs,
  };
}

function ensureCompetitiveProfile(profile, nowEpochMs, config = RATING_CONFIG) {
  profile.competitive ||= initialCompetitiveProfile(nowEpochMs, config);
  const competitive = profile.competitive;
  if (!Number.isFinite(competitive.hiddenRating)) {
    competitive.hiddenRating = config.initialRating;
  }
  competitive.stats ||= {};
  competitive.stats.matchesPlayed ||= 0;
  competitive.stats.totalWins ||= 0;
  competitive.stats.currentWinStreak ||= 0;
  competitive.stats.maxWinStreak ||= 0;

  const currentSeason = seasonForEpoch(nowEpochMs, config);
  if (competitive.season?.seasonId !== currentSeason.seasonId) {
    const previousSeasonEndRating = competitive.hiddenRating;
    competitive.hiddenRating = softResetRating(previousSeasonEndRating, config);
    competitive.season = {
      ...currentSeason,
      ratingAtSeasonStart: competitive.hiddenRating,
      previousSeasonEndRating,
      settlementVersion: config.seasonSettlementVersion,
    };
  }
  competitive.currentTier = tierForRating(competitive.hiddenRating, config);
  competitive.ratingBattle = competitive.currentTier === TIER.RATING_BATTLE;
  competitive.ratingConfigVersion = config.configVersion;
  competitive.updatedAtEpochMs = nowEpochMs;
  return competitive;
}

function expectedScore(rating, opponentRating, config = RATING_CONFIG) {
  return 1 / (1 + (10 ** ((opponentRating - rating) / config.eloScale)));
}

function pairwiseActual(player, opponent) {
  if (player.forfeited && opponent.forfeited) return 0.5;
  if (player.forfeited) return 0;
  if (opponent.forfeited) return 1;
  if (player.rank === opponent.rank) return 0.5;
  return player.rank < opponent.rank ? 1 : 0;
}

function calculatePairwiseRatingChanges(players, config = RATING_CONFIG) {
  return Object.fromEntries(players.map((player) => {
    const opponents = players.filter((candidate) => candidate.uid !== player.uid);
    const pairwise = opponents.map((opponent) => ({
      opponentUID: opponent.uid,
      actual: pairwiseActual(player, opponent),
      expected: expectedScore(player.rating, opponent.rating, config),
    }));
    const averageDifference = pairwise.length === 0
      ? 0
      : pairwise.reduce((sum, result) => sum + result.actual - result.expected, 0)
        / pairwise.length;
    const delta = Math.round(config.kFactor * averageDifference);
    const newRating = Math.max(config.minimumRating, player.rating + delta);
    return [player.uid, {
      preMatchRating: player.rating,
      delta: newRating - player.rating,
      newRating,
      currentTier: tierForRating(newRating, config),
      ratingBattle: newRating >= config.ratingBattleThreshold,
      pairwise,
    }];
  }));
}

function applyStats(competitive, { rank, forfeited }) {
  const stats = competitive.stats;
  const won = rank === 1 && !forfeited;
  stats.matchesPlayed += 1;
  if (won) {
    stats.totalWins += 1;
    stats.currentWinStreak += 1;
    stats.maxWinStreak = Math.max(stats.maxWinStreak, stats.currentWinStreak);
  } else {
    stats.currentWinStreak = 0;
  }
  return won;
}

function competitiveProjection(profile) {
  const competitive = profile.competitive;
  if (!competitive) return null;
  const stats = competitive.stats;
  return {
    currentTier: competitive.currentTier,
    ratingBattle: competitive.ratingBattle,
    ...(competitive.ratingBattle ? { displayRating: competitive.hiddenRating } : {}),
    stats: {
      matchesPlayed: stats.matchesPlayed,
      totalWins: stats.totalWins,
      maxWinStreak: stats.maxWinStreak,
      winRate: stats.matchesPlayed === 0 ? 0 : stats.totalWins / stats.matchesPlayed,
    },
    season: {
      seasonId: competitive.season.seasonId,
      startsAtEpochMs: competitive.season.startsAtEpochMs,
      endsAtEpochMs: competitive.season.endsAtEpochMs,
    },
  };
}

function npcSkillInputForRating(averageHiddenRating, config = RATING_CONFIG) {
  const offset = averageHiddenRating - config.initialRating;
  const npc = config.npcSkill;
  return {
    profileVersion: "phase-d1-rating-derived-1",
    sourceAverageHiddenRating: Math.round(averageHiddenRating),
    attemptPermille: npc.attemptPermille,
    accuracyPermille: Math.round(clamp(
      npc.accuracyBasePermille + offset * npc.accuracySlopePerRatingPoint,
      npc.minimumAccuracyPermille,
      npc.maximumAccuracyPermille
    )),
    reactionBaseMs: Math.round(clamp(
      npc.reactionBaseMs - offset * npc.reactionSlopePerRatingPoint,
      npc.minimumReactionMs,
      npc.maximumReactionMs
    )),
  };
}

function questionSelectionBoundary(tiers) {
  return {
    subject: "ENGLISH",
    currentTiers: [...new Set(tiers)].sort(),
    difficultyBand: null,
    mappingStatus: "PRODUCT_MAPPING_UNDECIDED",
  };
}

module.exports = {
  RATING_CONFIG,
  TIER,
  applyStats,
  calculatePairwiseRatingChanges,
  competitiveProjection,
  ensureCompetitiveProfile,
  initialCompetitiveProfile,
  npcSkillInputForRating,
  questionSelectionBoundary,
  seasonForEpoch,
  softResetRating,
  tierForRating,
};
