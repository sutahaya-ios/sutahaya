const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { PARTICIPANT_KIND, PHASE, PROTOCOL_VERSION } = require("../functions/competitive/constants");
const {
  RATING_CONFIG,
  TIER,
  applyStats,
  calculatePairwiseRatingChanges,
  ensureCompetitiveProfile,
  initialCompetitiveProfile,
  seasonForEpoch,
  softResetRating,
  tierForRating,
} = require("../functions/competitive/rating");
const { settleCompetitiveRoot } = require("../functions/competitive/settlement");

function ratingPlayer(uid, rating, rank, overrides = {}) {
  return { uid, rating, rank, forfeited: false, ...overrides };
}

function profile(uid, matchId, rating, nowEpochMs, stats = {}) {
  const competitive = initialCompetitiveProfile(nowEpochMs);
  competitive.hiddenRating = rating;
  competitive.currentTier = tierForRating(rating);
  competitive.ratingBattle = competitive.currentTier === TIER.RATING_BATTLE;
  competitive.stats = { ...competitive.stats, ...stats };
  return {
    uid,
    protocolVersion: PROTOCOL_VERSION,
    currentSession: {
      sessionId: `session-${uid}`,
      sessionEpoch: 1,
      state: "WAITING_PLAYERS",
      matchId,
      protocolVersion: PROTOCOL_VERSION,
    },
    competitive,
  };
}

function settlementRoot({
  matchId = "match-rating",
  ratings = [1_000, 1_000, 1_000, 1_000],
  ranks = [1, 2, 3, 4],
  forfeited = [],
  npcSlots = [],
  nowEpochMs = RATING_CONFIG.seasonEpochStartMs + 1,
  stats = {},
} = {}) {
  const participantOrder = ["p1", "p2", "p3", "p4"];
  const participants = {};
  const profiles = {};
  for (const [slot, uid] of participantOrder.entries()) {
    const isNPC = npcSlots.includes(slot);
    participants[uid] = {
      uid,
      slot,
      kind: isNPC ? PARTICIPANT_KIND.NPC : PARTICIPANT_KIND.HUMAN,
      sessionId: isNPC ? undefined : `session-${uid}`,
      sessionEpoch: isNPC ? undefined : 1,
      preMatchRating: ratings[slot],
      forfeited: forfeited.includes(uid),
    };
    if (!isNPC) {
      profiles[uid] = profile(uid, matchId, ratings[slot], nowEpochMs, stats[uid]);
    }
  }
  return {
    matches: {
      [matchId]: {
        private: {
          matchId,
          phase: PHASE.SETTLEMENT_PENDING,
          stateVersion: 10,
          serverSequence: 20,
          protocolVersion: PROTOCOL_VERSION,
          createdAtEpochMs: nowEpochMs - 1_000,
          requiresActiveSessionFence: true,
          participantOrder,
          participants,
          matchResult: {
            ranks: Object.fromEntries(participantOrder.map((uid, index) => [uid, ranks[index]])),
            forfeitedUIDs: forfeited,
          },
          settlement: { status: "CORE_RESULT_READY" },
        },
        public: { phase: PHASE.SETTLEMENT_PENDING },
      },
    },
    matchmaking: {
      private: { profiles, settlements: {} },
      public: Object.fromEntries(participantOrder
        .filter((_, slot) => !npcSlots.includes(slot))
        .map((uid) => [uid, { uid, state: "WAITING_PLAYERS" }])),
    },
    presence: { [matchId]: { p1: { status: "CONNECTED" } } },
  };
}

describe("Competitive Phase D-1 rating", () => {
  it("uses opponent MMR in four-player pairwise Elo and rewards an upset more", () => {
    const expected = calculatePairwiseRatingChanges([
      ratingPlayer("p1", 1_400, 1),
      ratingPlayer("p2", 1_200, 2),
      ratingPlayer("p3", 1_000, 3),
      ratingPlayer("p4", 800, 4),
    ]);
    const upset = calculatePairwiseRatingChanges([
      ratingPlayer("low", 800, 1),
      ratingPlayer("high", 1_400, 2),
      ratingPlayer("p3", 1_000, 3),
      ratingPlayer("p4", 1_000, 4),
    ]);
    assert.ok(expected.p1.delta > 0);
    assert.ok(expected.p4.delta < 0);
    assert.ok(upset.low.delta > expected.p1.delta);
    assert.ok(upset.high.delta < 0);
  });

  it("treats equal ranks and multiple forfeits as draws within each group", () => {
    const changes = calculatePairwiseRatingChanges([
      ratingPlayer("p1", 1_000, 1),
      ratingPlayer("p2", 1_000, 1),
      ratingPlayer("p3", 1_000, 2, { forfeited: true }),
      ratingPlayer("p4", 1_000, 3, { forfeited: true }),
    ]);
    assert.equal(changes.p1.delta, changes.p2.delta);
    assert.equal(changes.p3.delta, changes.p4.delta);
    assert.ok(changes.p1.delta > 0);
    assert.ok(changes.p3.delta < 0);
  });

  it("never crosses the configured rating floor", () => {
    const changes = calculatePairwiseRatingChanges([
      ratingPlayer("p1", 0, 4),
      ratingPlayer("p2", 1_000, 1),
      ratingPlayer("p3", 1_000, 2),
      ratingPlayer("p4", 1_000, 3),
    ]);
    assert.equal(changes.p1.newRating, RATING_CONFIG.minimumRating);
    assert.equal(changes.p1.delta, 0);
  });

  it("derives every tier and the Rating Battle boundary from server config", () => {
    assert.equal(tierForRating(0), TIER.BRONZE);
    assert.equal(tierForRating(RATING_CONFIG.tierThresholds.SILVER), TIER.SILVER);
    assert.equal(tierForRating(RATING_CONFIG.tierThresholds.GOLD), TIER.GOLD);
    assert.equal(tierForRating(RATING_CONFIG.tierThresholds.PLATINUM), TIER.PLATINUM);
    assert.equal(tierForRating(RATING_CONFIG.ratingBattleThreshold), TIER.RATING_BATTLE);
    assert.equal(tierForRating(RATING_CONFIG.ratingBattleThreshold - 1), TIER.PLATINUM);
  });

  it("supports promotion and demotion without a second rating engine", () => {
    const promoted = calculatePairwiseRatingChanges([
      ratingPlayer("target", RATING_CONFIG.tierThresholds.SILVER - 1, 1),
      ratingPlayer("p2", 1_000, 2),
      ratingPlayer("p3", 1_000, 3),
      ratingPlayer("p4", 1_000, 4),
    ]).target;
    const demoted = calculatePairwiseRatingChanges([
      ratingPlayer("target", RATING_CONFIG.tierThresholds.SILVER, 4),
      ratingPlayer("p2", 1_000, 1),
      ratingPlayer("p3", 1_000, 2),
      ratingPlayer("p4", 1_000, 3),
    ]).target;
    assert.equal(promoted.currentTier, TIER.SILVER);
    assert.equal(demoted.currentTier, TIER.BRONZE);
  });
});

describe("Competitive Phase D-1 stats and season", () => {
  it("counts sole/tied first as wins, loss as streak reset, and forfeit as no win", () => {
    const competitive = initialCompetitiveProfile(RATING_CONFIG.seasonEpochStartMs + 1);
    assert.equal(applyStats(competitive, { rank: 1, forfeited: false }), true);
    assert.equal(applyStats(competitive, { rank: 1, forfeited: false }), true);
    assert.equal(competitive.stats.currentWinStreak, 2);
    assert.equal(competitive.stats.maxWinStreak, 2);
    assert.equal(applyStats(competitive, { rank: 2, forfeited: false }), false);
    assert.equal(competitive.stats.currentWinStreak, 0);
    assert.equal(applyStats(competitive, { rank: 1, forfeited: true }), false);
    assert.equal(competitive.stats.totalWins, 2);
    assert.equal(competitive.stats.matchesPlayed, 4);
  });

  it("uses four-week seasons and rolls exactly at the end boundary", () => {
    const current = seasonForEpoch(RATING_CONFIG.seasonEpochStartMs + 1);
    const next = seasonForEpoch(current.endsAtEpochMs);
    assert.equal(current.endsAtEpochMs - current.startsAtEpochMs, 28 * 24 * 60 * 60 * 1_000);
    assert.notEqual(next.seasonId, current.seasonId);
    assert.equal(next.startsAtEpochMs, current.endsAtEpochMs);
  });

  it("soft-resets toward the base once and is retry-safe", () => {
    const firstSeason = seasonForEpoch(RATING_CONFIG.seasonEpochStartMs + 1);
    const profileValue = { competitive: initialCompetitiveProfile(firstSeason.startsAtEpochMs + 1) };
    profileValue.competitive.hiddenRating = 1_400;
    const expected = softResetRating(1_400);
    ensureCompetitiveProfile(profileValue, firstSeason.endsAtEpochMs);
    assert.equal(profileValue.competitive.hiddenRating, expected);
    assert.equal(profileValue.competitive.season.previousSeasonEndRating, 1_400);
    ensureCompetitiveProfile(profileValue, firstSeason.endsAtEpochMs + 1);
    assert.equal(profileValue.competitive.hiddenRating, expected);
  });
});

describe("Competitive Phase D-1 settlement", () => {
  it("settles rating, tiers, stats, session release and presence atomically", () => {
    const root = settlementRoot({ ratings: [1_095, 1_000, 1_000, 1_000] });
    const result = settleCompetitiveRoot(root, "match-rating", RATING_CONFIG.seasonEpochStartMs + 2);
    assert.equal(result.status, "SETTLED");
    assert.equal(result.root.matches["match-rating"].private.phase, PHASE.SETTLED);
    assert.equal(result.root.matchmaking.private.profiles.p1.competitive.currentTier, TIER.SILVER);
    assert.equal(result.root.matchmaking.private.profiles.p1.competitive.stats.totalWins, 1);
    assert.equal(result.root.matchmaking.private.profiles.p2.competitive.stats.currentWinStreak, 0);
    assert.equal(result.root.matchmaking.public.p1.state, "NOT_QUEUED");
    assert.equal(result.root.matchmaking.public.p1.matchId, undefined);
    assert.equal(result.root.presence["match-rating"], undefined);
    assert.equal(
      Object.hasOwn(result.root.matches["match-rating"].private.settlement, "playerResults"),
      false
    );
    assert.deepEqual(
      result.root.matchmaking.private.settlements["match-rating"].playerResults,
      result.settlement.playerResults
    );
  });

  it("does not double-apply duplicate or retry settlement", () => {
    const first = settleCompetitiveRoot(
      settlementRoot(),
      "match-rating",
      RATING_CONFIG.seasonEpochStartMs + 2
    );
    const rating = first.root.matchmaking.private.profiles.p1.competitive.hiddenRating;
    const matches = first.root.matchmaking.private.profiles.p1.competitive.stats.matchesPlayed;
    const duplicate = settleCompetitiveRoot(
      first.root,
      "match-rating",
      RATING_CONFIG.seasonEpochStartMs + 3
    );
    assert.equal(duplicate.changed, false);
    assert.equal(duplicate.status, "ALREADY_SETTLED");
    assert.equal(duplicate.root.matchmaking.private.profiles.p1.competitive.hiddenRating, rating);
    assert.equal(duplicate.root.matchmaking.private.profiles.p1.competitive.stats.matchesPlayed, matches);
  });

  it("ranks a forfeiter last for MMR and never awards a display-rank win", () => {
    const result = settleCompetitiveRoot(settlementRoot({
      ratings: [1_000, 1_000, 1_000, 1_000],
      ranks: [1, 2, 3, 4],
      forfeited: ["p1"],
    }), "match-rating", RATING_CONFIG.seasonEpochStartMs + 2);
    const p1 = result.settlement.playerResults.p1;
    assert.equal(p1.won, false);
    assert.ok(p1.ratingDelta < 0);
    assert.equal(p1.stats.totalWins, 0);
  });

  it("soft-resets a player crossing a season before applying settlement once", () => {
    const oldSeasonNow = RATING_CONFIG.seasonEpochStartMs + 1;
    const root = settlementRoot({ nowEpochMs: oldSeasonNow, ratings: [1_400, 1_000, 1_000, 1_000] });
    const nextSeasonNow = seasonForEpoch(oldSeasonNow).endsAtEpochMs;
    const result = settleCompetitiveRoot(root, "match-rating", nextSeasonNow);
    const p1Profile = result.root.matchmaking.private.profiles.p1.competitive;
    assert.equal(p1Profile.season.previousSeasonEndRating, 1_400);
    assert.equal(result.settlement.playerResults.p1.mmrBefore, softResetRating(1_400));
  });

  it("updates only human profiles in a mixed Human/NPC settlement", () => {
    const result = settleCompetitiveRoot(settlementRoot({
      npcSlots: [2, 3],
      ranks: [1, 2, 3, 4],
    }), "match-rating", RATING_CONFIG.seasonEpochStartMs + 2);
    assert.deepEqual(Object.keys(result.settlement.playerResults).sort(), ["p1", "p2"]);
    assert.equal(result.root.matchmaking.private.profiles.p3, undefined);
    assert.equal(result.root.matchmaking.private.profiles.p4, undefined);
  });
});
