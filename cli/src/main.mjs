/**
 * Process-level wiring: terminal restoration and the exit code.
 *
 * Kept out of `bin/` on purpose. The bin file has to run its Node version check
 * before any of this package is parsed, so it cannot statically import anything
 * from here — a static import is hoisted and its whole graph parsed first.
 */
import { main } from "./cli.mjs";
import { showCursor } from "./ui.mjs";

const restore = () => {
  showCursor();
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
};

export async function start(argv = process.argv.slice(2)) {
  process.on("exit", restore);

  // `exit` does not fire on SIGTERM or SIGHUP: their default disposition kills the
  // process outright. Closing the terminal window mid-prompt used to leave the
  // cursor hidden in whatever shell came next.
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.on(signal, () => {
      restore();
      process.exit(signal === "SIGINT" ? 130 : 1);
    });
  }

  // Observes without swallowing, so an unexpected crash still prints its trace.
  process.on("uncaughtExceptionMonitor", restore);

  try {
    process.exitCode = await main(argv);
  } catch (err) {
    restore();
    console.error(err);
    process.exitCode = 1;
  }
}
