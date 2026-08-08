/**
 * Terminal primitives: colour, glyphs, width-aware truncation.
 *
 * Hand-rolled rather than pulled from `picocolors` + `@clack/prompts`: this is an
 * `npx` tool, so every dependency is download time the user waits through before
 * seeing anything. Zero deps means the picker is on screen immediately.
 */
const stdout = process.stdout;
const ESC = "\x1b[";

export const colorEnabled =
  !process.env.NO_COLOR &&
  process.env.TERM !== "dumb" &&
  (stdout.isTTY || process.env.FORCE_COLOR === "1");

const wrap = (open, close) => (text) =>
  colorEnabled ? `${ESC}${open}m${text}${ESC}${close}m` : String(text);

export const c = {
  bold: wrap(1, 22),
  dim: wrap(2, 22),
  italic: wrap(3, 23),
  underline: wrap(4, 24),
  red: wrap(31, 39),
  green: wrap(32, 39),
  yellow: wrap(33, 39),
  blue: wrap(34, 39),
  magenta: wrap(35, 39),
  cyan: wrap(36, 39),
  gray: wrap(90, 39),
};

/** Claude's own accent, so the tool looks like it belongs next to Claude Code. */
export const accent = (text) =>
  colorEnabled ? `${ESC}38;2;217;119;87m${text}${ESC}39m` : String(text);

export const s = {
  bar: "│",
  barStart: "┌",
  barEnd: "└",
  step: "◇",
  active: "◆",
  error: "■",
  on: "◉",
  off: "○",
  pointer: "❯",
  tick: "✔",
  cross: "✖",
  warn: "▲",
  arrow: "→",
};

export const BADGES = {
  required: { label: "à installer en premier", color: c.magenta, icon: "★" },
  cost: { label: "payant", color: c.yellow, icon: "€" },
  sandbox: { label: "sandbox", color: c.yellow, icon: s.warn },
};

const ANSI = /\x1b\[[0-9;]*m/g;

/** Closes a colour left open by a cut — empty when colour is off, so that
 *  redirected output stays free of stray escape codes. */
const RESET = colorEnabled ? `${ESC}39m${ESC}22m` : "";

/** Visible length, ignoring colour codes. */
export const width = (text) => [...String(text).replace(ANSI, "")].length;

/** Truncates on visible width while keeping colour codes balanced. */
export function truncate(text, max) {
  const str = String(text);
  if (width(str) <= max) return str;

  let out = "";
  let visible = 0;
  let i = 0;
  while (i < str.length && visible < max - 1) {
    if (str[i] === "\x1b") {
      const end = str.indexOf("m", i);
      if (end === -1) break;
      out += str.slice(i, end + 1);
      i = end + 1;
      continue;
    }
    out += str[i];
    visible += 1;
    i += 1;
  }
  return `${out}${RESET}…`;
}

export const columns = () => Math.min(stdout.columns || 80, 110);

export const write = (text) => stdout.write(text);
export const hideCursor = () => stdout.isTTY && write(`${ESC}?25l`);
export const showCursor = () => stdout.isTTY && write(`${ESC}?25h`);

/** Erases the last `lines` rows so the next frame draws over them. */
export const eraseLines = (lines) => {
  if (lines > 0 && stdout.isTTY) write(`${ESC}${lines}A${ESC}J`);
};

/** Clears the current line, for in-place spinner updates. */
export const clearLine = () => write(`\r${ESC}K`);

export const intro = (title, subtitle) => {
  write("\n");
  write(
    `${c.gray(s.barStart)}  ${accent(c.bold(title))}` +
      `${subtitle ? `  ${c.gray(subtitle)}` : ""}\n`,
  );
  write(`${c.gray(s.bar)}\n`);
};

export const note = (text) => write(`${c.gray(s.bar)}  ${text}\n${c.gray(s.bar)}\n`);

export const outro = (text) => write(`${c.gray(s.barEnd)}  ${text}\n\n`);

export const cancel = (text) => write(`${c.gray(s.barEnd)}  ${c.red(text)}\n\n`);
