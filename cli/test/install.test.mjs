import { test } from "node:test";
import assert from "node:assert/strict";
import { setModelInvocation } from "../src/install.mjs";

const FM = ["---", "name: tdd", "description: Test-driven development.", "---", "", "# TDD", ""].join("\n");

test("adds the flag when the frontmatter has none", () => {
  const { text, patched } = setModelInvocation(FM, true);
  assert.equal(patched, true);
  assert.match(text, /^---\nname: tdd\n.*\ndisable-model-invocation: true\n---\n/s);
  assert.ok(text.endsWith("# TDD\n"), "body is preserved");
});

test("replaces an existing flag instead of duplicating it", () => {
  const withFlag = FM.replace("---\n\n# TDD", "disable-model-invocation: false\n---\n\n# TDD");
  const { text } = setModelInvocation(withFlag, true);
  assert.equal(text.match(/disable-model-invocation:/g).length, 1);
  assert.match(text, /disable-model-invocation: true/);
});

test("leaves the description untouched", () => {
  // A YAML round-trip would requote and reflow these; a line edit must not.
  const tricky = [
    "---",
    "name: storm-research",
    `description: 'Runs a 4-phase pipeline: five lenses -> map -> report. Says "storm this".'`,
    'argument-hint: "[topic]"',
    "---",
    "",
    "body",
    "",
  ].join("\n");
  const { text } = setModelInvocation(tricky, false);
  assert.ok(text.includes(`description: 'Runs a 4-phase pipeline: five lenses -> map -> report. Says "storm this".'`));
  assert.ok(text.includes('argument-hint: "[topic]"'));
});

test("round-trips CRLF files without mixing line endings", () => {
  // At least one skill in this repo came back from Windows with CRLF.
  const crlf = FM.replace(/\n/g, "\r\n");
  const { text, patched } = setModelInvocation(crlf, true);
  assert.equal(patched, true);
  assert.ok(text.includes("disable-model-invocation: true"));
  assert.equal(text.includes("\n"), true);
  assert.equal(/[^\r]\n/.test(text), false, "every LF is still preceded by CR");
});

test("does nothing when there is no frontmatter", () => {
  const { text, patched } = setModelInvocation("# just a heading\n", true);
  assert.equal(patched, false);
  assert.equal(text, "# just a heading\n");
});

test("does not mistake a horizontal rule in the body for a fence", () => {
  const withRule = "# heading\n\n---\n\nmore text\n";
  const { patched } = setModelInvocation(withRule, true);
  assert.equal(patched, false);
});
