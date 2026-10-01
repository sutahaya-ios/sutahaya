#!/usr/bin/env node

const { performance } = require("node:perf_hooks");

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

async function postJson(url, body, token) {
  const headers = { "content-type": "application/json" };
  if (token !== undefined) {
    headers["x-competitive-spike-token"] = token;
  }
  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : { nonJson: true };
  return { httpStatus: response.status, payload };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`ASSERTION_FAILED: ${message}`);
  }
}

async function main() {
  const controlUrl = requiredEnvironment("COMPETITIVE_V2_SPIKE_CONTROL_URL");
  const orderUrl = requiredEnvironment("COMPETITIVE_V2_SPIKE_ORDER_URL");
  const token = requiredEnvironment("COMPETITIVE_V2_SPIKE_TOKEN");
  const runId = requiredEnvironment("COMPETITIVE_V2_SPIKE_RUN_ID");

  const controlBody = {
    action: "status",
    runId,
    matchId: "preflight-control",
  };
  const withoutToken = await postJson(controlUrl, controlBody);
  assert(
    withoutToken.httpStatus === 401
      && withoutToken.payload.error === "UNAUTHORIZED",
    "Control without token must be rejected by Function token guard"
  );

  const invalidToken = await postJson(controlUrl, controlBody, "invalid-spike-token");
  assert(
    invalidToken.httpStatus === 401
      && invalidToken.payload.error === "UNAUTHORIZED",
    "Control with invalid token must be rejected by Function token guard"
  );

  const validControl = await postJson(controlUrl, controlBody, token);
  assert(
    validControl.httpStatus === 200
      && validControl.payload.status === "missing",
    "Control with valid token must reach Function"
  );

  const coldMatchId = "preflight-order-cold";
  const initialized = await postJson(controlUrl, {
    action: "initialize",
    runId,
    matchId: coldMatchId,
  }, token);
  assert(
    initialized.httpStatus === 200
      && initialized.payload.status === "initialized",
    "Control must initialize cold Order probe match"
  );

  const coldT0EpochMs = Date.now();
  const coldT0MonotonicMs = performance.now();
  const validOrder = await postJson(orderUrl, {
    runId,
    matchId: coldMatchId,
    playerId: "A",
    eventId: "preflight-cold-event",
    sessionId: "session-A",
    sessionEpoch: 1,
    buzz: true,
  }, token);
  const coldT3MonotonicMs = performance.now();
  assert(
    validOrder.httpStatus === 200
      && validOrder.payload.status === "accepted"
      && validOrder.payload.serverSequence === 1,
    "Order with valid token must complete one RTDB CAS"
  );

  const malformedOrder = await postJson(orderUrl, {}, token);
  assert(
    malformedOrder.httpStatus === 200
      && malformedOrder.payload.status === "rejected"
      && malformedOrder.payload.code === "MALFORMED_REQUEST",
    "Order must reject malformed request"
  );

  const unknownMatch = await postJson(orderUrl, {
    runId,
    matchId: "preflight-unknown-match",
    playerId: "A",
    eventId: "preflight-unknown-event",
    sessionId: "session-A",
    sessionEpoch: 1,
    buzz: true,
  }, token);
  assert(
    unknownMatch.httpStatus === 200
      && unknownMatch.payload.status === "rejected"
      && unknownMatch.payload.code === "UNKNOWN_MATCH",
    "Order must reject unknown match"
  );

  process.stdout.write(`${JSON.stringify({
    status: "passed",
    control: {
      withoutToken: withoutToken.httpStatus,
      invalidToken: invalidToken.httpStatus,
      validToken: validControl.httpStatus,
    },
    order: {
      validToken: validOrder.httpStatus,
      malformed: malformedOrder.payload.code,
      unknownMatch: unknownMatch.payload.code,
    },
    coldOrderProbe: {
      coldInstanceInvocation: validOrder.payload.runtime.coldInstanceInvocation,
      instanceAgeAtT1Ms: validOrder.payload.runtime.instanceAgeAtT1Ms,
      t1ToT2Ms: validOrder.payload.timing.t1ToT2Ms,
      t0ToT2MsApprox:
        validOrder.payload.timing.t2EpochMs - coldT0EpochMs,
      t0ToT3Ms: coldT3MonotonicMs - coldT0MonotonicMs,
      accessTokenMs: validOrder.payload.timing.accessTokenMs,
      rtdbCasMs: validOrder.payload.timing.rtdbCasMs,
    },
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
