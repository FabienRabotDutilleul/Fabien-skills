/**
 * Interactive prompts: a grouped, filterable multiselect and a single select.
 *
 * The multiselect is built for this collection specifically — 48 skills across 6
 * families, each with a long description and sometimes a warning. A flat list would
 * be unreadable, so entries stay grouped under their category, the description of
 * the highlighted row is shown in full underneath, and typing filters live.
 */
import readline from "node:readline";
import { c, s, BADGES, accent, columns, width, truncate, write, eraseLines, hideCursor, showCursor } from "./ui.mjs";

export const CANCEL = Symbol("cancel");

/** Runs a raw-mode session, restoring the terminal whatever happens. */
async function session(render) {
  const { stdin, stdout } = process;
  if (!stdin.isTTY) throw new Error("pas de terminal interactif");

  readline.emitKeypressEvents(stdin);
  const wasRaw = stdin.isRaw;
  stdin.setRawMode(true);
  stdin.resume();
  hideCursor();

  let drawn = 0;
  const paint = (frame) => {
    eraseLines(drawn);
    // Never paint taller than the window: a frame that overflows scrolls the
    // terminal on every repaint, out of reach of eraseLines, and each keypress
    // then leaks a stale copy of the top lines into the scrollback.
    let lines = frame.split("\n");
    const max = Math.max(1, (stdout.rows || 24) - 1);
    if (lines.length > max) lines = lines.slice(0, max);
    drawn = lines.length;
    write(`${lines.join("\n")}\n`);
  };

  try {
    return await new Promise((resolve) => {
      const onKey = (str, key) => render({ str, key, paint, done });
      const onResize = () => render({ str: null, key: { name: "resize" }, paint, done });

      function done(value) {
        stdin.off("keypress", onKey);
        stdout.off("resize", onResize);
        eraseLines(drawn);
        drawn = 0;
        resolve(value);
      }

      stdin.on("keypress", onKey);
      stdout.on("resize", onResize);
      render({ str: null, key: { name: "init" }, paint, done });
    });
  } finally {
    showCursor();
    stdin.setRawMode(wasRaw);
    stdin.pause();
  }
}

const isQuit = (key) => key.name === "escape" || (key.ctrl && (key.name === "c" || key.name === "d"));

const badgeTags = (skill) =>
  (skill.badges ?? [])
    .map((b) => BADGES[b.kind])
    .filter(Boolean)
    .map((b) => b.color(`${b.icon} ${b.label}`))
    .join(" ");

/**
 * @param {object} options
 * @param {Array} options.skills   entries from skills.json
 * @param {Set<string>} [options.preselected]
 */
export function multiselect({ title, skills, preselected = new Set() }) {
  const selected = new Set(preselected);
  let filter = "";
  let cursor = 0;
  let offset = 0;

  /** Flattens the filtered skills into headers + rows for rendering. */
  function build() {
    const needle = filter.toLowerCase();
    const matches = skills.filter(
      (skill) =>
        !needle ||
        skill.name.toLowerCase().includes(needle) ||
        skill.path.toLowerCase().includes(needle) ||
        skill.description.toLowerCase().includes(needle),
    );
    const rows = [];
    let category = null;
    for (const skill of matches) {
      if (skill.category !== category) {
        category = skill.category;
        rows.push({ type: "header", label: category });
      }
      rows.push({ type: "skill", skill });
    }
    return { rows, matches };
  }

  return session(({ key, str, paint, done }) => {
    let view = build();
    const selectable = view.rows.filter((r) => r.type === "skill");

    if (key.name !== "init" && key.name !== "resize") {
      if (isQuit(key)) return done(CANCEL);
      if (key.name === "return") return done([...selected]);

      if (key.name === "up") cursor -= 1;
      else if (key.name === "down") cursor += 1;
      else if (key.name === "pageup") cursor -= 10;
      else if (key.name === "pagedown") cursor += 10;
      else if (key.name === "home") cursor = 0;
      else if (key.name === "end") cursor = selectable.length - 1;
      else if (key.name === "space") {
        const row = selectable[cursor];
        if (row) {
          if (selected.has(row.skill.name)) selected.delete(row.skill.name);
          else selected.add(row.skill.name);
        }
      } else if (key.ctrl && key.name === "a") {
        const all = selectable.every((r) => selected.has(r.skill.name));
        for (const r of selectable) {
          if (all) selected.delete(r.skill.name);
          else selected.add(r.skill.name);
        }
      } else if (key.ctrl && key.name === "u") {
        filter = "";
        cursor = 0;
      } else if (key.name === "backspace") {
        filter = filter.slice(0, -1);
        cursor = 0;
      } else if (str && !key.ctrl && !key.meta && str >= " " && str !== "\x7f") {
        filter += str;
        cursor = 0;
      }

      view = build();
    }

    const rows = view.rows;
    const items = rows.filter((r) => r.type === "skill");
    cursor = Math.max(0, Math.min(cursor, items.length - 1));

    // Scroll the flattened row list so the highlighted skill stays visible along
    // with the header it belongs to. The budget is counted in *physical* lines —
    // a header renders on two (blank bar + label), a skill on one — because a
    // frame taller than the window scrolls the terminal on every repaint and
    // litters the scrollback with stale copies of itself.
    const cursorRow = rows.indexOf(items[cursor]);
    const cols = columns();
    const chrome = 9 + (filter ? 1 : 0); // title, bars, description, meta, help, trailing newline
    const budget = Math.max(4, (process.stdout.rows || 24) - chrome);
    const cost = (row) => (row.type === "header" ? 2 : 1);
    // Last row index (exclusive) that fits in the budget when starting at `from`.
    const endFrom = (from) => {
      let used = 0;
      let i = from;
      while (i < rows.length && used + cost(rows[i]) <= budget) used += cost(rows[i++]);
      return Math.max(i, from + 1); // always show at least the cursor row
    };
    if (cursorRow < offset) offset = Math.max(0, cursorRow - 1);
    while (offset < cursorRow && endFrom(offset) <= cursorRow) offset += 1;
    // Don't leave dead space at the bottom when the end of the list fits.
    while (offset > 0 && endFrom(offset - 1) >= rows.length) offset -= 1;
    const visible = rows.slice(offset, endFrom(offset));

    const bar = c.gray(s.bar);
    const out = [];
    out.push(
      truncate(
        `${accent(s.active)}  ${c.bold(title)}` +
          `  ${c.gray(`${selected.size} choisi${selected.size > 1 ? "s" : ""} · ${items.length}/${skills.length}`)}`,
        cols,
      ),
    );
    out.push(bar);

    if (filter) out.push(`${bar}  ${c.gray("filtre")} ${accent(filter)}${c.gray("▏")}`);

    if (items.length === 0) {
      out.push(`${bar}  ${c.gray("aucun skill ne correspond")}`);
    }

    for (const row of visible) {
      if (row.type === "header") {
        out.push(`${bar}`);
        out.push(`${bar}  ${c.dim(c.underline(row.label))}`);
        continue;
      }
      const { skill } = row;
      const isCursor = row === items[cursor];
      const isOn = selected.has(skill.name);
      const box = isOn ? c.green(s.on) : c.gray(s.off);
      const name = isCursor ? accent(c.bold(skill.name)) : isOn ? c.bold(skill.name) : skill.name;
      const pointer = isCursor ? accent(s.pointer) : " ";
      const tags = badgeTags(skill);
      const head = `${bar} ${pointer} ${box} ${name}`;
      const pad = " ".repeat(Math.max(1, 26 - width(head) + width(bar) + 2));
      const tail = tags ? `${pad}${tags}` : "";
      out.push(truncate(head + tail, cols));
    }

    const current = items[cursor]?.skill;
    out.push(bar);
    if (current) {
      out.push(truncate(`${bar}  ${c.dim(current.description)}`, cols));
      const meta = [
        c.gray(current.path),
        current.setup ? c.yellow(`setup : ${current.setup}`) : null,
      ]
        .filter(Boolean)
        .join(c.gray(" · "));
      out.push(truncate(`${bar}  ${meta}`, cols));
    } else {
      out.push(bar);
      out.push(bar);
    }
    out.push(bar);
    out.push(
      truncate(
        `${bar}  ${c.gray("↑↓ naviguer · espace choisir · ^a tout · taper pour filtrer · ⏎ valider · esc annuler")}`,
        cols,
      ),
    );

    paint(out.join("\n"));
  });
}

/** Single-choice prompt. `options` is `[{ value, label, hint }]`. */
export function select({ title, options, initial = 0 }) {
  let cursor = initial;

  return session(({ key, paint, done }) => {
    if (key.name !== "init" && key.name !== "resize") {
      if (isQuit(key)) return done(CANCEL);
      if (key.name === "return") return done(options[cursor].value);
      if (key.name === "up" || key.name === "left") cursor -= 1;
      if (key.name === "down" || key.name === "right") cursor += 1;
      cursor = (cursor + options.length) % options.length;
    }

    const bar = c.gray(s.bar);
    const cols = columns();
    const out = [truncate(`${accent(s.active)}  ${c.bold(title)}`, cols), bar];
    options.forEach((option, i) => {
      const on = i === cursor;
      const dot = on ? accent(s.on) : c.gray(s.off);
      const label = on ? accent(c.bold(option.label)) : option.label;
      const hint = option.hint ? `  ${c.gray(option.hint)}` : "";
      out.push(truncate(`${bar}  ${dot} ${label}${hint}`, cols));
    });
    out.push(bar);
    out.push(`${bar}  ${c.gray("↑↓ naviguer · ⏎ valider · esc annuler")}`);
    paint(out.join("\n"));
  });
}
