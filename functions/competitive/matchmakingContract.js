const { MAX_BODY_BYTES, MAX_ID_LENGTH, PROTOCOL_VERSION } = require("./constants");

const SAFE_ID = new RegExp(`^[A-Za-z0-9][A-Za-z0-9:_-]{0,${MAX_ID_LENGTH - 1}}$`);
const TYPES = new Set(["joinQueue", "cancelQueue"]);

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, allowed) {
  return Object.keys(value).every((key) => allowed.has(key));
}

function safeId(value) {
  return typeof value === "string" && SAFE_ID.test(value);
}

function validateMatchmakingIntent(value) {
  if (!plainObject(value)) return "INVALID_PAYLOAD";
  if (Buffer.byteLength(JSON.stringify(value), "utf8") > MAX_BODY_BYTES) {
    return "PAYLOAD_TOO_LARGE";
  }
  if (!exactKeys(value, new Set([
    "intentId",
    "type",
    "protocolVersion",
    "clientBuild",
    "sessionId",
    "sessionEpoch",
    "payload",
  ]))
      || !safeId(value.intentId)
      || !TYPES.has(value.type)
      || typeof value.protocolVersion !== "string"
      || !safeId(value.clientBuild)
      || !plainObject(value.payload)
      || !exactKeys(value.payload, new Set())) {
    return "INVALID_PAYLOAD";
  }
  if (value.protocolVersion !== PROTOCOL_VERSION) return "PROTOCOL_UNSUPPORTED";
  if (value.type === "joinQueue") {
    return value.sessionId === undefined && value.sessionEpoch === undefined
      ? null
      : "INVALID_PAYLOAD";
  }
  return safeId(value.sessionId)
    && Number.isSafeInteger(value.sessionEpoch)
    && value.sessionEpoch >= 1
    ? null
    : "INVALID_PAYLOAD";
}

module.exports = { validateMatchmakingIntent };
