import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

test("built package exposes both ESM and CommonJS entry points", async () => {
  const esm = await import("../dist/index.js");
  const require = createRequire(import.meta.url);
  const cjs = require("../dist-cjs/index.js");

  assert.equal(typeof esm.ControlKeelClient, "function");
  assert.equal(typeof cjs.ControlKeelClient, "function");
});
