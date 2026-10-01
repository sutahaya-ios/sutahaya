#!/usr/bin/env node

const { performance } = require("node:perf_hooks");

const CONCURRENT_PLAYERS = ["A", "B", "C", "D"];

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

function makeIntent(config, matchId, playerId, eventId) {
  return {
    runId: config.runId,
    matchId,
    playerId,
    eventId,
    sessionId: `session-${playerId}`,
    sessionEpoch: 1,
    buzz: true,
  };
}

async function sendIntent(config, intent) {
  const t0EpochMs = Date.now();
  const t0MonotonicMs = performance.now();
  const payload = await postJson(config.orderUrl, config.token, intent);
  const t3MonotonicMs = performance.now();
  const t0ToT3Ms = t3MonotonicMs - t0MonotonicMs;
  return {
    ...payload,
    driverTiming: {
      t0EpochMs,
      t3EpochMs: t0EpochMs + t0ToT3Ms,
      t0ToT2Ms: payload.timing.t2EpochMs - t0EpochMs,
      t0ToT3Ms,
    },
  };
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

function metricSummary(results, selector) {
  const values = results
    .map(selector)
    .filter((value) => Number.isFinite(value))
    .sort((left, right) => left - right);
  return {
    count: values.length,
    min: roundMetric(values[0] ?? null),
    p50: roundMetric(percentile(values, 0.50)),
    p95: roundMetric(percentile(values, 0.95)),
    max: roundMetric(values[values.length - 1] ?? null),
  };
}

function latencySummary(results) {
  return {
    t1ToT2Ms: metricSummary(results, (result) => result.timing.t1ToT2Ms),
    accessTokenMs: metricSummary(results, (result) => result.timing.accessTokenMs),
    rtdbCasMs: metricSummary(results, (result) => result.timing.rtdbCasMs),
    t0ToT2MsApprox: metricSummary(
      results,
      (result) => result.driverTiming.t0ToT2Ms
    ),
    t0ToT3Ms: metricSummary(results, (result) => result.driverTiming.t0ToT3Ms),
  };
}

function roundName(prefix, index) {
  return `${prefix}-${String(index + 1).padStart(3, "0")}`;
}

function assertFirstWinnerRound(results, matchId) {
  assert(results.length === 4, `${matchId}: expected four results`);
  const winners = results.filter(
    (result) => result.status === "accepted" && result.accepted === true
  );
  const losers = results.filter(
    (result) => result.status === "rejected"
      && result.accepted === false
      && result.code === "BUZZ_ALREADY_LOCKED"
  );
  assert(winners.length === 1, `${matchId}: expected exactly one winner`);
  assert(losers.length === 3, `${matchId}: expected exactly three locked losers`);
  assert(
    winners[0].serverSequence === 1 && winners[0].stateVersion === 1,
    `${matchId}: winner must own the only state transition`
  );
  assert(
    losers.every((result) => result.winnerPlayerId === winners[0].winnerPlayerId),
    `${matchId}: every loser must observe the same winner`
  );
  return { winner: winners[0], losers };
}

async function runConcurrentRound(config, matchId) {
  await control(config, "initialize", matchId);
  const results = await Promise.all(
    CONCURRENT_PLAYERS.map((playerId) => sendIntent(
      config,
      makeIntent(config, matchId, playerId, `${matchId}-${playerId}`)
    ))
  );
  const outcome = assertFirstWinnerRound(results, matchId);
  const status = await control(config, "status", matchId);
  assert(status.status === "found", `${matchId}: state must exist`);
  assert(status.state.serverSequence === 1, `${matchId}: sequence must increment once`);
  assert(status.state.stateVersion === 1, `${matchId}: stateVersion must increment once`);
  assert(status.state.phase === "ANSWERING", `${matchId}: state must be ANSWERING`);
  assert(
    status.state.winner.playerId === outcome.winner.winnerPlayerId,
    `${matchId}: persisted winner must match the accepted result`
  );
  assert(
    Object.keys(status.state.processedEvents || {}).length === 1,
    `${matchId}: only the winning event may be persisted`
  );
  return results;
}

async function runColdProbe(config) {
  const matchId = "cold-probe";
  await control(config, "initialize", matchId);
  const result = await sendIntent(
    config,
    makeIntent(config, matchId, "A", "cold-probe-A")
  );
  assert(result.status === "accepted", "cold probe must be accepted");
  assert(result.serverSequence === 1, "cold probe sequence must be 1");
  return result;
}

async function runSafetyChecks(config) {
  const duplicateMatchId = "check-duplicate";
  await control(config, "initialize", duplicateMatchId);
  const originalIntent = makeIntent(
    config,
    duplicateMatchId,
    "A",
    "duplicate-event-A"
  );
  const original = await sendIntent(config, originalIntent);
  const duplicate = await sendIntent(config, originalIntent);
  const duplicatePlayer = await sendIntent(
    config,
    makeIntent(config, duplicateMatchId, "A", "different-event-A")
  );
  const rejectedLoserIntent = makeIntent(
    config,
    duplicateMatchId,
    "B",
    "locked-loser-B"
  );
  const rejectedLoser = await sendIntent(config, rejectedLoserIntent);
  const rejectedLoserRetry = await sendIntent(config, rejectedLoserIntent);
  assert(original.status === "accepted", "original event must be accepted");
  assert(duplicate.status === "duplicate", "winning event retry must be duplicate");
  assert(
    duplicate.serverSequence === original.serverSequence,
    "winning event retry must preserve sequence"
  );
  assert(
    duplicatePlayer.status === "rejected"
      && duplicatePlayer.code === "DUPLICATE_PLAYER_BUZZ",
    "winner's second event must be rejected"
  );
  assert(
    rejectedLoser.code === "BUZZ_ALREADY_LOCKED"
      && rejectedLoserRetry.code === "BUZZ_ALREADY_LOCKED",
    "loser retry must remain rejected without overwriting winner"
  );

  const retryMatchId = "check-concurrent-retry";
  await control(config, "initialize", retryMatchId);
  const retryIntent = makeIntent(
    config,
    retryMatchId,
    "B",
    "concurrent-retry-B"
  );
  const concurrentRetry = await Promise.all([
    sendIntent(config, retryIntent),
    sendIntent(config, retryIntent),
  ]);
  assert(
    concurrentRetry.every((result) => ["accepted", "duplicate"].includes(result.status)),
    "concurrent identical retry must resolve as accepted or duplicate"
  );
  assert(
    concurrentRetry.every((result) => result.serverSequence === 1),
    "concurrent identical retry must preserve one sequence"
  );
  const retryState = await control(config, "status", retryMatchId);
  assert(retryState.state.serverSequence === 1, "concurrent retry must increment once");
  assert(
    Object.keys(retryState.state.processedEvents || {}).length === 1,
    "concurrent retry must persist one event"
  );

  const reopenMatchId = "check-reopen";
  await control(config, "initialize", reopenMatchId);
  const beforeReopen = await control(config, "status", reopenMatchId);
  const firstWinner = await sendIntent(
    config,
    makeIntent(config, reopenMatchId, "A", "reopen-first-A")
  );
  assert(firstWinner.status === "accepted", "first winner must be accepted");
  const reopened = await control(config, "reopenAfterIncorrect", reopenMatchId);
  assert(reopened.status === "reopened", "incorrect answer must reopen test state");
  const afterReopen = await control(config, "status", reopenMatchId);
  assert(afterReopen.state.phase === "QUESTION_OPEN", "reopened state must be open");
  assert(afterReopen.state.lockedOut.A === true, "incorrect player must be locked out");
  assert(afterReopen.state.eligiblePlayers.A === false, "incorrect player must be ineligible");
  assert(!afterReopen.state.winner, "reopened state must not retain the prior winner lock");
  assert(
    afterReopen.state.questionOpenedAtEpochMs
      === beforeReopen.state.questionOpenedAtEpochMs
      && afterReopen.state.questionDeadlineEpochMs
        === beforeReopen.state.questionDeadlineEpochMs,
    "reopen must preserve the original question timing"
  );
  const lockedOutRetry = await sendIntent(
    config,
    makeIntent(config, reopenMatchId, "A", "reopen-second-A")
  );
  const secondWinner = await sendIntent(
    config,
    makeIntent(config, reopenMatchId, "B", "reopen-second-B")
  );
  assert(
    lockedOutRetry.code === "PLAYER_LOCKED_OUT",
    "locked-out player must not win after reopen"
  );
  assert(
    secondWinner.status === "accepted" && secondWinner.winnerPlayerId === "B",
    "remaining eligible player must be able to win after reopen"
  );

  const staleMatchId = "check-stale-session";
  await control(config, "initialize", staleMatchId);
  const staleSession = await sendIntent(config, {
    ...makeIntent(config, staleMatchId, "C", "stale-session-C"),
    sessionEpoch: 2,
  });
  assert(
    staleSession.status === "rejected" && staleSession.code === "STALE_SESSION",
    "stale session must be rejected"
  );

  const malformed = await sendIntent(config, {
    runId: config.runId,
    matchId: "check-malformed",
    buzz: false,
  });
  assert(
    malformed.status === "rejected" && malformed.code === "MALFORMED_REQUEST",
    "malformed request must be rejected"
  );

  const unknownMatch = await sendIntent(
    config,
    makeIntent(config, "check-unknown-match", "D", "unknown-match-D")
  );
  assert(
    unknownMatch.status === "rejected" && unknownMatch.code === "UNKNOWN_MATCH",
    "unknown match must be rejected"
  );

  return {
    sequentialWinnerDuplicate: {
      originalStatus: original.status,
      retryStatus: duplicate.status,
      serverSequence: duplicate.serverSequence,
    },
    duplicatePlayer: {
      status: duplicatePlayer.status,
      code: duplicatePlayer.code,
    },
    rejectedLoserRetry: {
      statuses: [rejectedLoser.status, rejectedLoserRetry.status],
      codes: [rejectedLoser.code, rejectedLoserRetry.code],
    },
    concurrentIdenticalRetry: {
      statuses: concurrentRetry.map((result) => result.status),
      sequences: concurrentRetry.map((result) => result.serverSequence),
      persistedSequence: retryState.state.serverSequence,
    },
    reopenAfterIncorrect: {
      priorWinner: firstWinner.winnerPlayerId,
      lockedOutRetryCode: lockedOutRetry.code,
      nextWinner: secondWinner.winnerPlayerId,
      questionOpenedAtPreserved: true,
      questionDeadlinePreserved: true,
    },
    staleSession: {
      status: staleSession.status,
      code: staleSession.code,
    },
    malformed: {
      status: malformed.status,
      code: malformed.code,
    },
    unknownMatch: {
      status: unknownMatch.status,
      code: unknownMatch.code,
    },
  };
}

function runtimeSummary(results) {
  const instances = new Map();
  for (const result of results) {
    const instanceId = result.runtime.instanceId;
    const current = instances.get(instanceId) || {
      requests: 0,
      coldInstanceInvocations: 0,
    };
    current.requests += 1;
    if (result.runtime.coldInstanceInvocation) {
      current.coldInstanceInvocations += 1;
    }
    instances.set(instanceId, current);
  }
  return {
    instanceCount: instances.size,
    instances: Array.from(instances.entries()).map(([instanceId, value]) => ({
      instanceId,
      ...value,
    })),
  };
}

async function run(config) {
  if (config.cleanupOnly) {
    return control(config, "cleanup");
  }

  const startedAt = new Date().toISOString();
  const cleanup = { attempted: false, status: "kept" };
  try {
    const coldProbe = await runColdProbe(config);

    for (let index = 0; index < config.warmupRounds; index += 1) {
      await runConcurrentRound(config, roundName("warmup", index));
    }

    const measuredResults = [];
    for (let index = 0; index < config.measuredRounds; index += 1) {
      measuredResults.push(
        ...await runConcurrentRound(config, roundName("measured", index))
      );
    }

    const safety = await runSafetyChecks(config);
    const warmResults = measuredResults.filter(
      (result) => !result.runtime.coldInstanceInvocation
    );
    const coldDuringMeasured = measuredResults.filter(
      (result) => result.runtime.coldInstanceInvocation
    );
    const warmWinners = warmResults.filter((result) => result.status === "accepted");
    const warmLosers = warmResults.filter((result) => result.status === "rejected");
    const totalCasWriteAttempts = measuredResults.reduce(
      (total, result) => total + result.casWriteAttempts,
      0
    );
    const contentionRetries = measuredResults.reduce(
      (total, result) => total + result.contentionRetries,
      0
    );

    return {
      status: "complete",
      candidate: "A-functions-2nd-gen-rtdb-first-winner-lock",
      startedAt,
      completedAt: new Date().toISOString(),
      environment: {
        testOrigin: config.testOrigin,
        functionRegion: coldProbe.runtime.region,
        rtdbHost: coldProbe.runtime.rtdbHost,
        runId: config.runId,
        warmupRounds: config.warmupRounds,
        measuredRounds: config.measuredRounds,
        concurrentBuzzesPerRound: CONCURRENT_PLAYERS.length,
      },
      measurementNotes: {
        t0: "driver begins HTTP request",
        t1: "Cloud Function handler entry",
        t2: "winner lock or existing winner decision is available inside the Function",
        t3: "driver has parsed the HTTP response",
        t0ToT2: "approximate: client and server wall clocks must be synchronized",
        percentile: "nearest-rank",
        casWriteAttempts: "conditional RTDB PUT requests; reads that observe an existing winner are excluded",
      },
      coldProbe: {
        coldInstanceInvocation: coldProbe.runtime.coldInstanceInvocation,
        accessTokenCacheHit: coldProbe.runtime.accessTokenCacheHit,
        instanceId: coldProbe.runtime.instanceId,
        instanceStartedAtEpochMs: coldProbe.runtime.instanceStartedAtEpochMs,
        instanceAgeAtT1Ms: coldProbe.runtime.instanceAgeAtT1Ms,
        latency: latencySummary([coldProbe]),
      },
      warmMeasured: {
        includedIntentCount: warmResults.length,
        excludedColdInstanceIntentCount: coldDuringMeasured.length,
        winnerCount: warmWinners.length,
        loserCount: warmLosers.length,
        latency: latencySummary(warmResults),
        winnerLatency: latencySummary(warmWinners),
        loserLatency: latencySummary(warmLosers),
      },
      allMeasured: {
        intentCount: measuredResults.length,
        successfulRounds: config.measuredRounds,
        winnerCount: measuredResults.filter((result) => result.status === "accepted").length,
        loserCount: measuredResults.filter((result) => result.status === "rejected").length,
        winnerCollisionCount: 0,
        winnerOverwriteCount: 0,
        totalCasWriteAttempts,
        averageCasWriteAttemptsPerRound: roundMetric(
          totalCasWriteAttempts / config.measuredRounds
        ),
        totalDecisionLoopAttempts: measuredResults.reduce(
          (total, result) => total + result.attempts,
          0
        ),
        contentionRetryCount: contentionRetries,
        contentionRetryObserved: contentionRetries > 0,
        latency: latencySummary(measuredResults),
        runtime: runtimeSummary(measuredResults),
      },
      safety,
      engineeringTargets: {
        serverEntryToOrderingP95IdealMs: 150,
        clientRoundTripP95ProvisionalMs: 300,
      },
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

module.exports = { run };
