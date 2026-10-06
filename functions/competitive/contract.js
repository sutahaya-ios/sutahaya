const {
  MAX_BODY_BYTES,
  MAX_ID_LENGTH,
  PROTOCOL_VERSION,
} = require("./constants");

const SAFE_ID = new RegExp(`^[A-Za-z0-9][A-Za-z0-9:_-]{0,${MAX_ID_LENGTH - 1}}$`);
const CLIENT_INTENTS = new Set(["joinMatch", "ready", "submitAnswer", "leave"]);

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, allowed) {
  return Object.keys(value).every((key) => allowed.has(key));
}

function safeId(value) {
  return typeof value === "string" && SAFE_ID.test(value);
}

function validateCommon(data, allowedTypes) {
  if (!plainObject(data)) return "INVALID_PAYLOAD";
  if (Buffer.byteLength(JSON.stringify(data), "utf8") > MAX_BODY_BYTES) {
    return "PAYLOAD_TOO_LARGE";
  }
  const allowedKeys = new Set([
    "intentId",
    "type",
    "protocolVersion",
    "clientBuild",
    "sessionId",
    "sessionEpoch",
    "matchId",
    "questionId",
    "stateVersion",
    "lastSeenServerSequence",
    "payload",
  ]);
  if (!exactKeys(data, allowedKeys)
      || !safeId(data.intentId)
      || !allowedTypes.has(data.type)
      || typeof data.protocolVersion !== "string"
      || !safeId(data.clientBuild)
      || !safeId(data.sessionId)
      || !Number.isSafeInteger(data.sessionEpoch)
      || data.sessionEpoch < 1
      || !safeId(data.matchId)
      || !plainObject(data.payload)) {
    return "INVALID_PAYLOAD";
  }
  if (data.protocolVersion !== PROTOCOL_VERSION) return "PROTOCOL_UNSUPPORTED";
  if (data.questionId !== undefined && !safeId(data.questionId)) return "INVALID_PAYLOAD";
  if (data.stateVersion !== undefined
      && (!Number.isSafeInteger(data.stateVersion) || data.stateVersion < 0)) {
    return "INVALID_PAYLOAD";
  }
  if (data.lastSeenServerSequence !== undefined
      && (!Number.isSafeInteger(data.lastSeenServerSequence)
        || data.lastSeenServerSequence < 0)) {
    return "INVALID_PAYLOAD";
  }
  return null;
}

function validateClientIntent(data) {
  const commonError = validateCommon(data, CLIENT_INTENTS);
  if (commonError) return commonError;
  if (data.type === "joinMatch") {
    return exactKeys(data.payload, new Set(["assignmentTicket"]))
      && safeId(data.payload.assignmentTicket)
      ? null
      : "INVALID_PAYLOAD";
  }
  if (data.type === "submitAnswer") {
    return exactKeys(data.payload, new Set(["answerId"]))
      && safeId(data.payload.answerId)
      && safeId(data.questionId)
      && Number.isSafeInteger(data.stateVersion)
      ? null
      : "INVALID_PAYLOAD";
  }
  return exactKeys(data.payload, new Set()) ? null : "INVALID_PAYLOAD";
}

function validateReconcileIntent(data) {
  const commonError = validateCommon(data, new Set(["reconcile"]));
  if (commonError) return commonError;
  return exactKeys(data.payload, new Set()) ? null : "INVALID_PAYLOAD";
}

module.exports = {
  safeId,
  validateClientIntent,
  validateReconcileIntent,
};
