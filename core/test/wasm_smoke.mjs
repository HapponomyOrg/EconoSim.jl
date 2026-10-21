// Node check for the EconoSimCore wasm smoke module.
//
// Usage:
//   node core/test/wasm_smoke.mjs /tmp/econosim_core_smoke.wasm
//
// The module must instantiate without an imports object (import-free).

import fs from "node:fs";
import assert from "node:assert/strict";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node core/test/wasm_smoke.mjs <path-to-wasm>");
  process.exit(2);
}

const bytes = fs.readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes);

assert.equal(typeof instance.exports.sumsy_smoke, "function");
assert.equal(typeof instance.exports.balance_smoke, "function");

// Native result: 10 SuMSy periods, GI 2000, demurrage 1%, interval 30.
assert.equal(instance.exports.sumsy_smoke(10n), 191235851n);
assert.equal(instance.exports.balance_smoke(12345n), 12345n);

console.log("wasm smoke OK");
