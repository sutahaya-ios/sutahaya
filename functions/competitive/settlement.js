const { PARTICIPANT_KIND, PHASE, SETTLEMENT_VERSION } = require("./constants");
const {
  RATING_CONFIG,
  applyStats,
  calculatePairwiseRatingChanges,
  competitiveProjection,
  ensureCompetitiveProfile,
} = require("./rating");

function clone(value) {
  return JSON.parse(JSON.stringify(value ?? {}));
}

function settleCompetitiveRoot(input, matchId, nowEpochMs, config = RATING_CONFIG) {
  const root = clone(input);
  const match = root.matches?.[matchId];
  if (!match?.private) {
    return { root, changed: false, status: "MATCH_NOT_FOUND" };
  }
  root.matchmaking ||= {};
  root.matchmaking.private ||= {};
  root.matchmaking.private.profiles ||= {};
  root.matchmaking.private.settlements ||= {};
  root.matchmaking.public ||= {};

  const existing = root.matchmaking.private.settlements[matchId];
  if (existing?.status === "SETTLED" || match.private.phase === PHASE.SETTLED) {
    return { root, changed: false, status: "ALREADY_SETTLED", settlement: existing };
  }
  if (match.private.phase !== PHASE.SETTLEMENT_PENDING || !match.private.matchResult) {
    return { root, changed: false, status: "NOT_READY" };
  }

  const participants = match.private.participantOrder.map((uid) => {
    const participant = match.private.participants[uid];
    const isHuman = participant.kind !== PARTICIPANT_KIND.NPC;
    let rating = participant.preMatchRating;
    if (isHuman) {
      let profile = root.matchmaking.private.profiles[uid];
      if (!profile && !match.private.requiresActiveSessionFence) {
        profile = {
          uid,
          createdAtEpochMs: match.private.createdAtEpochMs,
          accountStatus: "TEST_MATCH",
          protocolVersion: match.private.protocolVersion,
          currentSession: {
            sessionId: participant.sessionId,
            sessionEpoch: participant.sessionEpoch,
            state: "WAITING_PLAYERS",
            matchId,
            protocolVersion: match.private.protocolVersion,
          },
        };
        root.matchmaking.private.profiles[uid] = profile;
      }
      const session = profile?.currentSession;
      if (!profile || !session
          || session.matchId !== matchId
          || session.sessionId !== participant.sessionId
          || session.sessionEpoch !== participant.sessionEpoch) {
        throw new Error("SETTLEMENT_SESSION_FENCE_MISMATCH");
      }
      rating = ensureCompetitiveProfile(profile, nowEpochMs, config).hiddenRating;
    }
    if (!Number.isFinite(rating)) rating = config.initialRating;
    return {
      uid,
      kind: participant.kind || PARTICIPANT_KIND.HUMAN,
      rating,
      rank: match.private.matchResult.ranks[uid],
      forfeited: Boolean(participant.forfeited),
    };
  });
  const changes = calculatePairwiseRatingChanges(participants, config);
  const playerResults = {};

  for (const participant of participants) {
    if (participant.kind === PARTICIPANT_KIND.NPC) continue;
    const profile = root.matchmaking.private.profiles[participant.uid];
    const competitive = profile.competitive;
    const ratingChange = changes[participant.uid];
    competitive.hiddenRating = ratingChange.newRating;
    competitive.currentTier = ratingChange.currentTier;
    competitive.ratingBattle = ratingChange.ratingBattle;
    competitive.updatedAtEpochMs = nowEpochMs;
    const won = applyStats(competitive, participant);

    const session = profile.currentSession;
    session.state = "FINISHED";
    session.matchId = null;
    session.updatedAtEpochMs = nowEpochMs;
    profile.updatedAtEpochMs = nowEpochMs;
    root.matchmaking.public[participant.uid] = {
      ...(root.matchmaking.public[participant.uid] || {}),
      uid: participant.uid,
      state: "NOT_QUEUED",
      sessionId: session.sessionId,
      sessionEpoch: session.sessionEpoch,
      protocolVersion: session.protocolVersion,
      updatedAtEpochMs: nowEpochMs,
      competitive: competitiveProjection(profile),
    };
    delete root.matchmaking.public[participant.uid].matchId;
    delete root.matchmaking.public[participant.uid].assignmentTicket;
    delete root.matchmaking.public[participant.uid].queuedAtEpochMs;
    playerResults[participant.uid] = {
      rank: participant.rank,
      forfeited: participant.forfeited,
      won,
      mmrBefore: ratingChange.preMatchRating,
      ratingDelta: ratingChange.delta,
      mmrAfter: ratingChange.newRating,
      currentTier: ratingChange.currentTier,
      ratingBattle: ratingChange.ratingBattle,
      stats: { ...competitive.stats },
      seasonId: competitive.season.seasonId,
    };
  }

  const settlement = {
    settlementId: `${matchId}:${SETTLEMENT_VERSION}`,
    settlementVersion: SETTLEMENT_VERSION,
    formulaVersion: config.formulaVersion,
    configVersion: config.configVersion,
    status: "SETTLED",
    settledAtEpochMs: nowEpochMs,
    seasonId: Object.values(playerResults)[0]?.seasonId || null,
    playerResults,
  };
  root.matchmaking.private.settlements[matchId] = settlement;
  match.private.phase = PHASE.SETTLED;
  match.private.settlement = {
    settlementId: settlement.settlementId,
    settlementVersion: settlement.settlementVersion,
    formulaVersion: settlement.formulaVersion,
    configVersion: settlement.configVersion,
    status: settlement.status,
    settledAtEpochMs: settlement.settledAtEpochMs,
    seasonId: settlement.seasonId,
  };
  match.private.stateVersion += 1;
  match.private.serverSequence += 1;
  match.private.audit ||= {};
  match.private.audit[String(match.private.serverSequence)] = {
    eventId: `rating-settlement-${matchId}`,
    eventType: "ratingSettlement",
    matchId,
    serverSequence: match.private.serverSequence,
    stateBefore: PHASE.SETTLEMENT_PENDING,
    stateAfter: PHASE.SETTLED,
    accepted: true,
    authorityTimestamp: nowEpochMs,
    settlementVersion: SETTLEMENT_VERSION,
    formulaVersion: config.formulaVersion,
    configVersion: config.configVersion,
  };
  match.public ||= {};
  match.public.phase = PHASE.SETTLED;
  match.public.stateVersion = match.private.stateVersion;
  match.public.serverSequence = match.private.serverSequence;
  match.public.settlement = {
    status: settlement.status,
    settlementId: settlement.settlementId,
  };
  if (root.presence) delete root.presence[matchId];
  return { root, changed: true, status: "SETTLED", settlement };
}

module.exports = { settleCompetitiveRoot };
