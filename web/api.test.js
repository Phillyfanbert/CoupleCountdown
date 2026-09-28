// Every S.api.x(...) the web app calls must exist on makeApi in data.js.
// A refactor once deleted joinPreview from data.js while app.js still called
// it: nothing else failed, and the live Join screen broke. Text-based, so it
// runs without the Firebase SDK. Run: node --test web/api.test.js
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (name) => readFileSync(new URL(name, import.meta.url), "utf8");

test("every data call the app makes exists in data.js", () => {
  const app = read("./app.js");
  const data = read("./data.js");
  const api = data.slice(data.indexOf("export function makeApi"));
  const defined = new Set([...api.matchAll(/^ {4}(?:async )?(\w+)\(/gm)].map((m) => m[1]));
  // Plain properties on the returned object (e.g. coupleRef,).
  for (const m of api.matchAll(/^ {4}(\w+),$/gm)) defined.add(m[1]);
  const used = new Set([...app.matchAll(/S\.api\.(\w+)\(/g)].map((m) => m[1]));
  assert.ok(used.size > 10, "found the app's data calls");
  const missing = [...used].filter((name) => !defined.has(name));
  assert.deepEqual(missing, [], `app.js calls data functions that don't exist: ${missing.join(", ")}`);
});
