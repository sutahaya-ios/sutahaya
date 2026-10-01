#!/usr/bin/env node

const CONCURRENT_PLAYERS = ["A", "B", "C", "D"];
const MAX_MEASURED_ATTEMPTS_FACTOR = 2;

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function positiveInteger(name, fallback) {
  const rawValue = process.env[name];
  if (rawValue === undefined) {
    return fallback;
  }
  const value = Number(rawValue);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function safeId(value, name) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(value)) {
    throw new Error(`${name} must match the Spike safe identifier format`);
  }
  return value;
}

function endpoint(value, name) {
  const url = new URL(value);
  if (url.protocol !== "https:"
      && process.env.COMPETITIVE_V2_SPIKE_ALLOW_HTTP !== "1") {
    throw new Error(`${name} must use HTTPS`);
  }
  return url.toString();
}

function loadConfiguration() {
  return {
    controlUrl: endpoint(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_CONTROL_URL"),
      "COMPETITIVE_V2_SPIKE_CONTROL_URL"
    ),
    orderUrl: endpoint(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_ORDER_URL"),
      "COMPETITIVE_V2_SPIKE_ORDER_URL"
    ),
    token: requiredEnvironment("COMPETITIVE_V2_SPIKE_TOKEN"),
    runId: safeId(
      requiredEnvironment("COMPETITIVE_V2_SPIKE_RUN_ID"),
      "COMPETITIVE_V2_SPIKE_RUN_ID"
    ),
    testOrigin: requiredEnvironment("COMPETITIVE_V2_SPIKE_TEST_ORIGIN"),
    warmupRounds: positiveInteger("COMPETITIVE_V2_SPIKE_WARMUP_ROUNDS", 5),
    measuredRounds: positiveInteger("COMPETITIVE_V2_SPIKE_MEASURED_ROUNDS", 40),
    keepData: process.env.COMPETITIVE_V2_SPIKE_KEEP_DATA === "1",
    cleanupOnly: process.env.COMPETITIVE_V2_SPIKE_CLEANUP_ONLY === "1",
  };
}

async function postJson(url, token, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-competitive-spike-token": token,
    },
    body: JSON.stringify(body),
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error(`HTTP ${response.status} returned non-JSON response`);
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}

async function control(config, action, matchId) {
  const body = { action, runId: config.runId };
  if (matchId !== undefined) {
    body.matchId = matchId;
  }
  return postJson(config.controlUrl, config.token, body);
}

function makeIntent(config, matchId, playerId) {
  return {
    runId: config.runId,
    matchId,
    playerId,
    eventId: `${matchId}-${playerId}`,
    sessionId: `session-${playerId}`,
    sessionEpoch: 1,
    buzz: true,
  };
}

async function sendIntent(config, matchId, playerId) {
  const payload = await postJson(
    config.orderUrl,
    config.token,
    makeIntent(config, matchId, playerId)
  );
  return { playerId, ...payload };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`ASSERTION_FAILED: ${message}`);
  }
}

function percentile(sortedValues, ratio) {
  if (sortedValues.length === 0) {
    return null;
  }
  const index = Math.max(0, Math.ceil(sortedValues.length * ratio) - 1);
  return sortedValues[index];
}

function roundMetric(value) {
  return value === null ? null : Number(value.toFixed(3));
}

function metricSummary(values) {
  const sortedValues = values
    .filter((value) => Number.isFinite(value))
    .sort((left, right) => left - right);
  return {
    count: sortedValues.length,
    min: roundMetric(sortedValues[0] ?? null),
    p50: roundMetric(percentile(sortedValues, 0.50)),
    p95: roundMetric(percentile(sortedValues, 0.95)),
    max: roundMetric(sortedValues[sortedValues.length - 1] ?? null),
  };
}

function analyzeRound(results, matchId) {
  assert(results.length === 4, `${matchId}: expected four results`);
  assert(
    results.every((result) => Number.isFinite(result.timing?.t1HighResolutionEpochMs)),
    `${matchId}: every result must include high-resolution T1`
  );
  const winners = results.filter(
    (result) => result.status === "accepted" && result.accepted === true
  );
  const losers = results.filter(
    (result) => result.status === "rejected"
      && result.accepted === false
      && result.code === "BUZZ_ALREADY_LOCKED"
  );
  assert(winners.length === 1, `${matchId}: expected exactly one winner`);
  assert(losers.length === 3, `${matchId}: expected exactly three losers`);

  const winner = winners[0];
  const sorted = [...results].sort((left, right) => (
    left.timing.t1HighResolutionEpochMs - right.timing.t1HighResolutionEpochMs
      || left.playerId.localeCompare(right.playerId)
  ));
  const earliestT1 = sorted[0].timing.t1HighResolutionEpochMs;
  const earliestPlayers = sorted
    .filter((result) => result.timing.t1HighResolutionEpochMs === earliestT1)
    .map((result) => result.playerId);
  const winnerWasEarliest = earliestPlayers.includes(winner.playerId);
  const earliest = sorted[0];
  const winnerGapMs = winner.timing.t1HighResolutionEpochMs - earliestT1;
  const instanceIds = [...new Set(results.map((result) => result.runtime.instanceId))];

  return {
    matchId,
    winnerPlayerId: winner.playerId,
    winnerT1HighResolutionEpochMs: winner.timing.t1HighResolutionEpochMs,
    winnerInstanceId: winner.runtime.instanceId,
    winnerLock: {
      status: winner.status,
      accepted: winner.accepted,
      serverSequence: winner.serverSequence,
      stateVersion: winner.stateVersion,
    },
    earliestPlayerIds: earliestPlayers,
    earliestT1HighResolutionEpochMs: earliestT1,
    earliestInstanceId: earliest.runtime.instanceId,
    exactEarliestTie: earliestPlayers.length > 1,
    winnerWasEarliest,
    winnerGapMs: roundMetric(winnerGapMs),
    earliestWinnerDifferentInstance:
      earliest.runtime.instanceId !== winner.runtime.instanceId,
    instanceCount: instanceIds.length,
    instanceIds,
    hasColdInstanceInvocation: results.some(
      (result) => result.runtime.coldInstanceInvocation
    ),
    requests: results.map((result) => ({
      playerId: result.playerId,
      t1EpochMs: result.timing.t1EpochMs,
      t1HighResolutionEpochMs: result.timing.t1HighResolutionEpochMs,
      result: result.status,
      accepted: result.accepted,
      reason: result.code ?? null,
      observedWinnerPlayerId: result.winnerPlayerId,
      functionRegion: result.runtime.region,
      functionInstanceId: result.runtime.instanceId,
      functionInvocationOrdinal: result.runtime.invocationOrdinal,
      coldInstanceInvocation: result.runtime.coldInstanceInvocation,
      winnerLockSequence: result.serverSequence ?? result.observedSequence ?? null,
      winnerLockStateVersion:
        result.stateVersion ?? result.observedStateVersion ?? null,
    })),
  };
}

async function runConcurrentRound(config, matchId) {
  await control(config, "initialize", matchId);
  const results = await Promise.all(
    CONCURRENT_PLAYERS.map((playerId) => sendIntent(config, matchId, playerId))
  );
  return analyzeRound(results, matchId);
}

function roundName(prefix, index) {
  return `${prefix}-${String(index + 1).padStart(3, "0")}`;
}

function countByPredicate(values, predicate) {
  return values.reduce((count, value) => count + (predicate(value) ? 1 : 0), 0);
}

function summarize(rounds) {
  const matched = rounds.filter((round) => round.winnerWasEarliest);
  const mismatches = rounds.filter((round) => !round.winnerWasEarliest);
  const mismatchGaps = mismatches.map((round) => round.winnerGapMs);
  const singleInstanceRounds = rounds.filter((round) => round.instanceCount === 1);
  const multiInstanceRounds = rounds.filter((round) => round.instanceCount > 1);
  const sameInstanceMismatches = mismatches.filter(
    (round) => !round.earliestWinnerDifferentInstance
  );
  const differentInstanceMismatches = mismatches.filter(
    (round) => round.earliestWinnerDifferentInstance
  );

  return {
    measuredRounds: rounds.length,
    earliestT1WinnerMatchCount: matched.length,
    earliestT1WinnerMatchRate: roundMetric(matched.length / rounds.length),
    mismatchCount: mismatches.length,
    exactEarliestTieRoundCount: countByPredicate(
      rounds,
      (round) => round.exactEarliestTie
    ),
    mismatchGapMs: metricSummary(mismatchGaps),
    mismatchGapCumulativeBuckets: {
      within10Ms: countByPredicate(mismatchGaps, (gap) => gap <= 10),
      within20Ms: countByPredicate(mismatchGaps, (gap) => gap <= 20),
      within30Ms: countByPredicate(mismatchGaps, (gap) => gap <= 30),
      within50Ms: countByPredicate(mismatchGaps, (gap) => gap <= 50),
      over50Ms: countByPredicate(mismatchGaps, (gap) => gap > 50),
      over100Ms: countByPredicate(mismatchGaps, (gap) => gap > 100),
    },
    mismatchGapExclusiveBuckets: {
      within10Ms: countByPredicate(mismatchGaps, (gap) => gap <= 10),
      over10To20Ms: countByPredicate(mismatchGaps, (gap) => gap > 10 && gap <= 20),
      over20To30Ms: countByPredicate(mismatchGaps, (gap) => gap > 20 && gap <= 30),
      over30To50Ms: countByPredicate(mismatchGaps, (gap) => gap > 30 && gap <= 50),
      over50To100Ms: countByPredicate(mismatchGaps, (gap) => gap > 50 && gap <= 100),
      over100Ms: countByPredicate(mismatchGaps, (gap) => gap > 100),
    },
    functionInstances: {
      distinctInstanceCount: new Set(
        rounds.flatMap((round) => round.instanceIds)
      ).size,
      singleInstanceRoundCount: singleInstanceRounds.length,
      singleInstanceMismatchCount: countByPredicate(
        singleInstanceRounds,
        (round) => !round.winnerWasEarliest
      ),
      multiInstanceRoundCount: multiInstanceRounds.length,
      multiInstanceMismatchCount: countByPredicate(
        multiInstanceRounds,
        (round) => !round.winnerWasEarliest
      ),
      mismatchEarliestWinnerSameInstanceCount: sameInstanceMismatches.length,
      mismatchEarliestWinnerDifferentInstanceCount:
        differentInstanceMismatches.length,
    },
  };
}

async function run(config) {
  if (config.cleanupOnly) {
    return control(config, "cleanup");
  }

  const startedAt = new Date().toISOString();
  const cleanup = { attempted: false, status: "kept" };
  try {
    for (let index = 0; index < config.warmupRounds; index += 1) {
      await runConcurrentRound(config, roundName("warmup-fidelity", index));
    }

    const measuredRounds = [];
    const excludedColdRounds = [];
    const maxAttempts = config.measuredRounds * MAX_MEASURED_ATTEMPTS_FACTOR;
    let attempt = 0;
    while (measuredRounds.length < config.measuredRounds && attempt < maxAttempts) {
      const round = await runConcurrentRound(
        config,
        roundName("measured-fidelity", attempt)
      );
      attempt += 1;
      if (round.hasColdInstanceInvocation) {
        excludedColdRounds.push(round);
      } else {
        measuredRounds.push(round);
      }
    }
    assert(
      measuredRounds.length === config.measuredRounds,
      `expected ${config.measuredRounds} warm rounds, got ${measuredRounds.length}`
    );

    return {
      status: "complete",
      candidate: "A-rtdb-first-winner-ordering-fidelity",
      startedAt,
      completedAt: new Date().toISOString(),
      environment: {
        testOrigin: config.testOrigin,
        functionRegion: measuredRounds[0].requests[0].functionRegion,
        rtdbRegion: "asia-southeast1",
        runId: config.runId,
        warmupRounds: config.warmupRounds,
        measuredWarmRounds: config.measuredRounds,
        concurrentBuzzesPerRound: CONCURRENT_PLAYERS.length,
        excludedColdRoundCount: excludedColdRounds.length,
      },
      measurementNotes: {
        t1: "performance.timeOrigin + performance.now() at Function handler entry",
        authority: "RTDB conditional PUT winner lock; client timestamps are not used",
        clockLimit:
          "T1 is wall-clock anchored per Function instance; cross-instance clocks are not a perfectly shared fairness clock",
        observationWriteImpact:
          "No extra RTDB write was added for fidelity observation",
        percentile: "nearest-rank",
      },
      summary: summarize(measuredRounds),
      roundObservations: measuredRounds,
      excludedColdRounds: excludedColdRounds.map((round) => round.matchId),
      cleanup,
    };
  } finally {
    if (!config.keepData) {
      cleanup.attempted = true;
      cleanup.status = "pending";
      try {
        const result = await control(config, "cleanup");
        cleanup.status = result.status;
      } catch (error) {
        cleanup.status = "failed";
        cleanup.error = error.message;
      }
    }
  }
}

async function main() {
  const config = loadConfiguration();
  const result = await run(config);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { analyzeRound, run, summarize };
