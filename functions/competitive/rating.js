const RATING_CONFIG = Object.freeze({
  configVersion: "competitive-rating-d2-1",
  formulaVersion: "pairwise-elo-tier-weighted-v2",
  initialRating: 1_000,
  minimumRating: 0,
  kFactor: 40,
  eloScale: 400,
  tierThresholds: Object.freeze({
    SILVER: 1_200,
    GOLD: 1_400,
    PLATINUM: 1_600,
  }),
  ratingBattleThreshold: 1_800,
  lossMultipliers: Object.freeze({
    BRONZE: 0.35,
    SILVER: 0.55,
    GOLD: 0.75,
    PLATINUM: 1,
    RATING_BATTLE: 1,
  }),
  humanWeights: Object.freeze({
    1: 0.5,
    2: 2 / 3,
    3: 5 / 6,
    4: 1,
  }),
  npcFillWaitMs: Object.freeze({
    BRONZE: 5_000,
    SILVER: 10_000,
    GOLD: null,
    PLATINUM: null,
    RATING_BATTLE: null,
  }),
  questionDurationMs: Object.freeze({
    BRONZE: 8_000,
    SILVER: 5_000,
    GOLD: 5_000,
    PLATINUM: 5_000,
    RATING_BATTLE: 5_000,
  }),
  npcAnswerRemainingMs: Object.freeze({
    BRONZE: 3_000,
    SILVER: null,
    GOLD: null,
    PLATINUM: null,
    RATING_BATTLE: null,
  }),
  npcNormalAnswerElapsedMs: Object.freeze({
    BRONZE: 5_000,
    SILVER: 4_100,
    GOLD: null,
    PLATINUM: null,
    RATING_BATTLE: null,
  }),
  npcFastAnswerElapsedMs: Object.freeze({
    BRONZE: 3_000,
    SILVER: 2_600,
    GOLD: null,
    PLATINUM: null,
    RATING_BATTLE: null,
  }),
  npcReactionReferenceMs: Object.freeze({
    BRONZE: 700,
    SILVER: 610,
    GOLD: null,
    PLATINUM: null,
    RATING_BATTLE: null,
  }),
  difficultyRanges: Object.freeze({
    BRONZE: Object.freeze({ minimum: 1, maximum: 2 }),
    SILVER: Object.freeze({ minimum: 2, maximum: 3 }),
    GOLD: Object.freeze({ minimum: 3, maximum: 4 }),
    PLATINUM: Object.freeze({ minimum: 4, maximum: 5 }),
    RATING_BATTLE: Object.freeze({ minimum: 5, maximum: 5 }),
  }),
  seasonSoftResetFactor: 0.75,
  seasonDurationMs: 28 * 24 * 60 * 60 * 1_000,
  seasonEpochStartMs: Date.UTC(2026, 0, 5),
  seasonSettlementVersion: "competitive-season-d2-1",
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

function platinumPromotionEligible(competitive, config = RATING_CONFIG) {
  const matches = competitive.season?.platinumSeasonMatches || 0;
  const wins = competitive.season?.platinumSeasonWins || 0;
  return competitive.hiddenRating >= config.ratingBattleThreshold
    && matches > 0
    && wins / matches > 0.5;
}

function tierForCompetitiveProfile(competitive, config = RATING_CONFIG, {
  preserveCurrentRatingBattle = false,
} = {}) {
  if (competitive.hiddenRating < config.ratingBattleThreshold) {
    return tierForRating(competitive.hiddenRating, config);
  }
  if (preserveCurrentRatingBattle && competitive.currentTier === TIER.RATING_BATTLE) {
    return TIER.RATING_BATTLE;
  }
  return platinumPromotionEligible(competitive, config)
    ? TIER.RATING_BATTLE
    : TIER.PLATINUM;
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
      platinumSeasonMatches: 0,
      platinumSeasonWins: 0,
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
      platinumSeasonMatches: 0,
      platinumSeasonWins: 0,
      settlementVersion: config.seasonSettlementVersion,
    };
  } else {
    competitive.season.platinumSeasonMatches ||= 0;
    competitive.season.platinumSeasonWins ||= 0;
  }
  const preserveCurrentRatingBattle = competitive.ratingConfigVersion === config.configVersion;
  competitive.currentTier = tierForCompetitiveProfile(competitive, config, {
    preserveCurrentRatingBattle,
  });
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

function deterministicRound(value) {
  return value < 0 ? Math.ceil(value - 0.5) : Math.floor(value + 0.5);
}

function humanWeightForCount(humanCount, config = RATING_CONFIG) {
  return config.humanWeights[humanCount] ?? 1;
}

function lossMultiplierForTier(tier, config = RATING_CONFIG) {
  return config.lossMultipliers[tier] ?? 1;
}

function calculatePairwiseRatingChanges(players, config = RATING_CONFIG) {
  const humanCount = players.filter(
    (player) => player.kind !== "NPC"
  ).length;
  const humanWeight = humanWeightForCount(humanCount, config);
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
    const rawDelta = config.kFactor * averageDifference;
    const preMatchTier = player.preMatchTier || tierForRating(player.rating, config);
    const lossMultiplier = rawDelta < 0
      ? lossMultiplierForTier(preMatchTier, config)
      : 1;
    const weightedDelta = rawDelta * lossMultiplier * humanWeight;
    const roundedDelta = deterministicRound(weightedDelta);
    const newRating = Math.max(config.minimumRating, player.rating + roundedDelta);
    const finalDelta = newRating - player.rating;
    return [player.uid, {
      preMatchRating: player.rating,
      preMatchTier,
      rawDelta,
      lossMultiplier,
      humanWeight,
      weightedDelta,
      finalDelta,
      delta: finalDelta,
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

function applyPlatinumSeasonStats(competitive, { preMatchTier, rank, forfeited }) {
  if (preMatchTier !== TIER.PLATINUM) return;
  competitive.season.platinumSeasonMatches += 1;
  if (rank === 1 && !forfeited) competitive.season.platinumSeasonWins += 1;
}

function ratingProgress(competitive, config = RATING_CONFIG) {
  const currentRating = competitive.hiddenRating;
  const currentTier = competitive.currentTier;
  const boundaries = {
    [TIER.BRONZE]: {
      tierFloor: config.initialRating,
      nextTierThreshold: config.tierThresholds.SILVER,
    },
    [TIER.SILVER]: {
      tierFloor: config.tierThresholds.SILVER,
      nextTierThreshold: config.tierThresholds.GOLD,
    },
    [TIER.GOLD]: {
      tierFloor: config.tierThresholds.GOLD,
      nextTierThreshold: config.tierThresholds.PLATINUM,
    },
    [TIER.PLATINUM]: {
      tierFloor: config.tierThresholds.PLATINUM,
      nextTierThreshold: config.ratingBattleThreshold,
    },
  };
  const boundary = boundaries[currentTier];
  if (!boundary) {
    return {
      currentRating,
      tierFloor: config.ratingBattleThreshold,
    };
  }
  const range = boundary.nextTierThreshold - boundary.tierFloor;
  return {
    currentRating,
    tierFloor: boundary.tierFloor,
    nextTierThreshold: boundary.nextTierThreshold,
    progressFraction: clamp((currentRating - boundary.tierFloor) / range, 0, 1),
    pointsToNextTier: Math.max(0, boundary.nextTierThreshold - currentRating),
  };
}

function competitiveProjection(profile) {
  const competitive = profile.competitive;
  if (!competitive) return null;
  const stats = competitive.stats;
  return {
    currentTier: competitive.currentTier,
    ratingBattle: competitive.ratingBattle,
    ...ratingProgress(competitive),
    ...(competitive.ratingBattle ? { displayRating: competitive.hiddenRating } : {}),
    stats: {
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
  const tier = tierForRating(averageHiddenRating, config);
  const reactionBaseMs = Math.round(clamp(
    npc.reactionBaseMs - offset * npc.reactionSlopePerRatingPoint,
    npc.minimumReactionMs,
    npc.maximumReactionMs
  ));
  const reactionReferenceMs = config.npcReactionReferenceMs[tier];
  const reactionAdjustmentMs = Number.isFinite(reactionReferenceMs)
    ? reactionBaseMs - reactionReferenceMs
    : 0;
  const normalAnswerElapsedMs = config.npcNormalAnswerElapsedMs[tier];
  const fastAnswerElapsedMs = config.npcFastAnswerElapsedMs[tier];
  return {
    profileVersion: "phase-d2-rating-derived-1",
    sourceAverageHiddenRating: Math.round(averageHiddenRating),
    attemptPermille: npc.attemptPermille,
    accuracyPermille: Math.round(clamp(
      npc.accuracyBasePermille + offset * npc.accuracySlopePerRatingPoint,
      npc.minimumAccuracyPermille,
      npc.maximumAccuracyPermille
    )),
    reactionBaseMs,
    answerRemainingMs: config.npcAnswerRemainingMs[tier] ?? null,
    normalAnswerElapsedMs: Number.isFinite(normalAnswerElapsedMs)
      ? normalAnswerElapsedMs + reactionAdjustmentMs
      : null,
    fastAnswerElapsedMs: Number.isFinite(fastAnswerElapsedMs)
      ? fastAnswerElapsedMs + Math.round(reactionAdjustmentMs / 2)
      : null,
  };
}

function questionDurationMsForTier(tier, config = RATING_CONFIG) {
  return config.questionDurationMs[tier] ?? 5_000;
}

function highestTier(tiers) {
  const order = [
    TIER.BRONZE,
    TIER.SILVER,
    TIER.GOLD,
    TIER.PLATINUM,
    TIER.RATING_BATTLE,
  ];
  return tiers.reduce((highest, tier) => (
    order.indexOf(tier) > order.indexOf(highest) ? tier : highest
  ), TIER.BRONZE);
}

function npcFillWaitMsForTiers(tiers, config = RATING_CONFIG) {
  return config.npcFillWaitMs[highestTier(tiers)] ?? null;
}

function questionSelectionBoundary(averageHiddenRating, config = RATING_CONFIG) {
  const matchTier = tierForRating(averageHiddenRating, config);
  const difficultyBand = config.difficultyRanges[matchTier];
  return {
    subject: "ENGLISH",
    source: "BUNDLED_ENGLISH_WORDS_V1",
    matchTier,
    sourceAverageHiddenRating: Math.round(averageHiddenRating),
    difficultyBand: { ...difficultyBand },
    mappingStatus: "PRODUCT_MAPPING_CONFIRMED",
  };
}

module.exports = {
  RATING_CONFIG,
  TIER,
  applyPlatinumSeasonStats,
  applyStats,
  calculatePairwiseRatingChanges,
  competitiveProjection,
  deterministicRound,
  ensureCompetitiveProfile,
  humanWeightForCount,
  initialCompetitiveProfile,
  lossMultiplierForTier,
  npcFillWaitMsForTiers,
  npcSkillInputForRating,
  platinumPromotionEligible,
  questionDurationMsForTier,
  questionSelectionBoundary,
  ratingProgress,
  seasonForEpoch,
  softResetRating,
  tierForCompetitiveProfile,
  tierForRating,
};
