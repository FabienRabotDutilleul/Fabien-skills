import { test } from "node:test";
import assert from "node:assert/strict";
import { width, truncate, colorEnabled } from "../src/ui.mjs";
import { rawUrl } from "../src/registry.mjs";

test("width ignores colour codes", () => {
  assert.equal(width("abc"), 3);
  assert.equal(width("\x1b[32mabc\x1b[39m"), 3);
});

test("width counts accents and box glyphs as one column", () => {
  assert.equal(width("écrasé"), 6);
  assert.equal(width("│ ◉ tdd"), 7);
});

test("truncate leaves short strings alone", () => {
  assert.equal(truncate("abc", 10), "abc");
});

test("truncate cuts on visible width, not byte length", () => {
  const cut = truncate("\x1b[32maaaaaaaaaa\x1b[39m", 5);
  assert.equal(width(cut), 5, "the ellipsis counts toward the budget");
  assert.ok(cut.endsWith("…"));
});

test("truncate emits no escape codes when colour is off", () => {
  // Tests run without a TTY, so colour is disabled and output may be redirected.
  assert.equal(colorEnabled, false);
  assert.ok(!truncate("a".repeat(40), 10).includes("\x1b"));
});

test("rawUrl encodes the folder that contains an ampersand", () => {
  const url = rawUrl("owner/repo", "main", "windows&bash-tools/anti-sleep/SKILL.md");
  assert.ok(url.includes("windows%26bash-tools"), url);
  assert.ok(!url.includes("&"), "a bare & would truncate the path");
});

test("rawUrl keeps separators intact", () => {
  assert.equal(
    rawUrl("FabienRabotDutilleul/Fabien-skills", "main", "engineering/tdd/SKILL.md"),
    "https://raw.githubusercontent.com/FabienRabotDutilleul/Fabien-skills/main/engineering/tdd/SKILL.md",
  );
});
