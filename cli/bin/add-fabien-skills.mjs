#!/usr/bin/env node
/*
 * Entry point, and nothing else.
 *
 * Deliberately ES5-only, with no static import of this package's own code. Two
 * reasons, both load-bearing:
 *
 *   - a static `import` is hoisted: its entire module graph is parsed before the
 *     first statement of this file runs, so a version check placed above one can
 *     never fire — the user gets a SyntaxError from a file they have never heard of
 *   - `engines` is advisory. npm prints EBADENGINE and runs the CLI anyway, so the
 *     only thing that actually enforces a Node floor is a check like this one
 *
 * The floor is 20.18 because that is where `util.styleText` learned to read
 * NO_COLOR / FORCE_COLOR / isTTY, which is what decides colour output.
 */
var parts = process.versions.node.split(".");
var major = Number(parts[0]);
var minor = Number(parts[1]);

// Mirrors `engines` exactly: ^20.18.0 || >=22.8.0. Node 21 and 22.0–22.7 are out
// too — they never received the styleText change, so they would colourise piped
// output instead of failing loudly.
var supported = major >= 23 || (major === 22 && minor >= 8) || (major === 20 && minor >= 18);

if (!supported) {
  console.error(
    "add-fabien-skills a besoin de Node ^20.18 ou >= 22.8 — tu tournes sur " +
      process.versions.node + "."
  );
  console.error("  nvm install 22     (ou https://nodejs.org)");
  process.exit(1);
}

import("../src/main.mjs").then(
  function (mod) {
    return mod.start();
  },
  function (err) {
    console.error(err);
    process.exitCode = 1;
  }
);
