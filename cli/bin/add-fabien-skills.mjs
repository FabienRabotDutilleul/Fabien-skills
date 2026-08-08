#!/usr/bin/env node
import { main } from "../src/cli.mjs";
import { showCursor } from "../src/ui.mjs";

// Raw mode hides the cursor; a ctrl-c that escapes the prompt loop must not leave
// the user's terminal without one.
const restore = () => {
  showCursor();
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
};
process.on("exit", restore);
process.on("SIGINT", () => {
  restore();
  process.exit(130);
});

try {
  process.exitCode = await main(process.argv.slice(2));
} catch (err) {
  restore();
  console.error(err);
  process.exitCode = 1;
}
