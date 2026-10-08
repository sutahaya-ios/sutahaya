const { REGION } = require("./constants");

const FUNCTION_OPTIONS = Object.freeze({
  region: REGION,
  memory: "256MiB",
  cpu: 1,
  timeoutSeconds: 30,
  minInstances: 0,
  maxInstances: 20,
  // Phase A-2/BではApp Check境界だけを作り、Production enforcementは有効化しない。
  enforceAppCheck: false,
});

module.exports = { FUNCTION_OPTIONS };
