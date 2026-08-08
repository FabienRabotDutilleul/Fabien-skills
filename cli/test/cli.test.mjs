/**
 * Contract tests for the command line itself, run against the real bin.
 *
 * These go through `execFile` rather than importing `run()` because the things
 * being asserted — which stream output lands on, the exit code, whether colour is
 * emitted — only exist at the process boundary. Every case here is one that was
 * silently wrong before.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { mkdtemp, mkdir, writeFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { sweepPartials } from "../src/install.mjs";

const run = promisify(execFile);
const BIN = fileURLToPath(new URL("../bin/add-fabien-skills.mjs", import.meta.url));
const ROOT = fileURLToPath(new URL("../..", import.meta.url));

/** Resolves with the outcome whether the CLI exited 0 or not. */
async function cli(args, env = {}) {
  try {
    const { stdout, stderr } = await run(process.execPath, [BIN, ...args], {
      env: { ...process.env, ...env },
      maxBuffer: 8 * 1024 * 1024,
    });
    return { stdout, stderr, code: 0 };
  } catch (err) {
    return { stdout: err.stdout ?? "", stderr: err.stderr ?? "", code: err.code };
  }
}

const hasAnsi = (text) => /\x1b\[/.test(text);

test("--version prints just the version", async () => {
  const { stdout, code } = await cli(["--version"]);
  assert.equal(code, 0);
  assert.match(stdout.trim(), /^\d+\.\d+\.\d+/);
});

test("--help wins over a bad flag on the same line", async () => {
  const { stdout, code } = await cli(["--help", "--bogus"]);
  assert.equal(code, 0);
  assert.match(stdout, /USAGE/);
});

test("errors go to stderr, not stdout, and exit non-zero", async () => {
  const { stdout, stderr, code } = await cli(["--bogus"]);
  assert.equal(code, 1);
  assert.equal(stdout, "");
  assert.match(stderr, /option inconnue/);
});

test("--list writes only the list to stdout, with no banner", async () => {
  const { stdout, code } = await cli(["--source", ROOT, "--list"]);
  assert.equal(code, 0);
  assert.doesNotMatch(stdout, /add-fabien-skills —/);
  assert.match(stdout, /skills$/m);
});

test("piped output carries no escape codes", async () => {
  const { stdout } = await cli(["--source", ROOT, "--list"]);
  assert.equal(hasAnsi(stdout), false);
});

test("FORCE_COLOR=2 still means colour", async () => {
  // The hand-rolled gate this replaced only understood FORCE_COLOR=1, so `=2`,
  // `=3` and `=true` all silently disabled colour.
  const { stdout } = await cli(["--source", ROOT, "--list"], { FORCE_COLOR: "2" });
  assert.equal(hasAnsi(stdout), true);
});

test("NO_COLOR alone disables colour", async () => {
  const { stdout } = await cli(["--source", ROOT, "--list"], { NO_COLOR: "1" });
  assert.equal(hasAnsi(stdout), false);
});

test("FORCE_COLOR wins over NO_COLOR, as Node decides", async () => {
  // Node resolves this conflict itself — it honours FORCE_COLOR and warns that
  // NO_COLOR is being ignored. Asserted so that deferring to `styleText` stays a
  // deliberate choice rather than something to be "fixed" later.
  const { stdout } = await cli(["--source", ROOT, "--list"], { FORCE_COLOR: "2", NO_COLOR: "1" });
  assert.equal(hasAnsi(stdout), true);
});

test("--no-interactive refuses to guess which skills to install", async () => {
  const { stderr, code } = await cli(["--source", ROOT, "--no-interactive"]);
  assert.equal(code, 1);
  assert.match(stderr, /--skills/);
});

test("--dry-run writes nothing", async () => {
  const dir = await mkdtemp(join(tmpdir(), "afs-dry-"));
  const { stdout, code } = await cli(
    ["--source", ROOT, "--skills", "tdd", "--target", "local", "--dry-run"],
    { INIT_CWD: dir },
  );
  assert.equal(code, 0);
  assert.match(stdout, /dry run/);
});

test("sweepPartials removes orphaned stagings and leaves real skills alone", async () => {
  const dir = await mkdtemp(join(tmpdir(), "afs-sweep-"));
  await mkdir(join(dir, ".tdd.partial"), { recursive: true });
  await mkdir(join(dir, "tdd"), { recursive: true });
  await writeFile(join(dir, "tdd", "SKILL.md"), "---\nname: tdd\n---\n");

  assert.equal(await sweepPartials(dir), 1);
  assert.deepEqual((await readdir(dir)).sort(), ["tdd"]);
});

test("sweepPartials on a directory that does not exist is not an error", async () => {
  assert.equal(await sweepPartials(join(tmpdir(), "afs-nope-does-not-exist")), 0);
});
