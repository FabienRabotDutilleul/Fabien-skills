/**
 * Writing skills to disk.
 *
 * A skill is a folder holding a SKILL.md. Claude Code discovers them in
 * `~/.claude/skills/<name>` (every project) or `<projet>/.claude/skills/<name>`
 * (this project only). Installing is therefore: fetch the files, write them under
 * the target, and set `disable-model-invocation` in the frontmatter.
 */
import { mkdir, writeFile, rm, chmod, readdir, rename, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { readSkillFile } from "./registry.mjs";

export const targetDir = (target, cwd = process.cwd()) =>
  target === "global"
    ? join(homedir(), ".claude", "skills")
    : join(resolve(cwd), ".claude", "skills");

/** True when `<dir>/<name>` already holds something. */
export async function existsAt(dir, name) {
  try {
    await stat(join(dir, name));
    return true;
  } catch {
    return false;
  }
}

/**
 * Rewrites `disable-model-invocation` inside the YAML frontmatter.
 *
 * A targeted line edit rather than a YAML round-trip: reserialising would reflow
 * every skill's carefully written description, and the CLI stays dependency-free.
 * Returns the text unchanged when there is no frontmatter to patch.
 */
export function setModelInvocation(text, value) {
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const normalized = text.replace(/\r\n/g, "\n");
  const match = /^---\n([\s\S]*?)\n---(\n[\s\S]*)?$/.exec(normalized);
  if (!match) return { text, patched: false };

  const body = match[2] ?? "";
  const lines = match[1]
    .split("\n")
    .filter((line) => !/^\s*disable-model-invocation\s*:/.test(line));
  lines.push(`disable-model-invocation: ${value}`);

  const rebuilt = `---\n${lines.join("\n")}\n---${body}`;
  return { text: eol === "\n" ? rebuilt : rebuilt.replace(/\n/g, eol), patched: true };
}

/**
 * Removes stagings orphaned by a run that was killed mid-download. `installSkill`
 * cleans up its own on failure, but not one left by a SIGKILL, and not one left by
 * a *different* skill.
 */
export async function sweepPartials(dir) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return 0;
  }
  let swept = 0;
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (!entry.name.startsWith(".") || !entry.name.endsWith(".partial")) continue;
    await rm(join(dir, entry.name), { recursive: true, force: true });
    swept += 1;
  }
  return swept;
}

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else yield path;
  }
}

/**
 * Installs one skill. Downloads into a sibling `.<name>.partial` first and swaps it
 * in at the end, so a connection that drops halfway cannot leave a half-written
 * skill that Claude Code would happily load.
 */
export async function installSkill(index, skill, dir, { dmi, onFile } = {}) {
  const dest = join(dir, skill.name);
  const staging = join(dir, `.${skill.name}.partial`);

  await rm(staging, { recursive: true, force: true });
  await mkdir(staging, { recursive: true });

  try {
    // Small files, many of them: a bounded pool keeps it fast without opening 143
    // sockets at once on the heaviest skill.
    const queue = [...skill.files];
    const workers = Array.from({ length: Math.min(8, queue.length) }, async () => {
      for (let file = queue.shift(); file; file = queue.shift()) {
        const bytes = await readSkillFile(index, skill, file);
        const path = join(staging, file.path);
        await mkdir(dirname(path), { recursive: true });

        if (file.path === "SKILL.md" && dmi !== null) {
          const { text } = setModelInvocation(bytes.toString("utf8"), dmi);
          await writeFile(path, text);
        } else {
          await writeFile(path, bytes);
        }
        if (file.exec) await chmod(path, 0o755);
        onFile?.(file);
      }
    });
    await Promise.all(workers);

    await rm(dest, { recursive: true, force: true });
    await mkdir(dirname(dest), { recursive: true });
    await rename(staging, dest);
  } catch (err) {
    await rm(staging, { recursive: true, force: true });
    throw err;
  }

  let written = 0;
  for await (const _ of walk(dest)) written += 1;
  return { dest, written };
}
