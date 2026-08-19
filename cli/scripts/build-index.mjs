#!/usr/bin/env node
/**
 * build-index.mjs — regenerates `skills.json` at the repo root.
 *
 * `skills.json` is the reference the `add-fabien-skills` CLI reads. It is fetched
 * from raw.githubusercontent.com in a single request, so the picker opens instantly
 * without cloning: the repo tarball weighs ~16 MB, almost all of it media that a
 * given install does not need. Each entry therefore carries its own file list, and
 * the CLI downloads only the files of the skills that were actually picked.
 *
 *   node cli/scripts/build-index.mjs          # write skills.json
 *   node cli/scripts/build-index.mjs --check  # fail if it is stale (for CI)
 */
import { readFile, writeFile, stat } from "node:fs/promises";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { parse as parseYaml } from "yaml";

const REPO_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const OUT = join(REPO_ROOT, "skills.json");
const REPO = "FabienRabotDutilleul/Fabien-skills";
const REF = "main";

/** Directories that never hold an installable skill. */
const PRUNE = new Set([".git", "node_modules", "__pycache__", ".venv", "venv"]);

/**
 * Curated badges. Kept here rather than in each SKILL.md so that the warnings the
 * README already states stay in one editable place instead of being duplicated
 * into 48 frontmatters. Keys are skill paths; `*` suffix matches a whole folder.
 */
const BADGES = {
  "agent-ops/global-agent-guardrails": [
    { kind: "required", label: "à installer en premier sur une machine neuve" },
  ],
  "kb/youtube/watch": [
    { kind: "cost", label: "clé API Whisper — coûte de l'argent et beaucoup de tokens" },
  ],
  "kb/youtube/channel-to-kb-supadata": [
    { kind: "cost", label: "API managée payante — les autres channel-to-kb* sont gratuits" },
  ],
  "productivity/learning/lquiz": [
    { kind: "required", label: "requiert le skill quiz installé à côté (../quiz/) et lavish-axi" },
  ],
  "research/*": [
    { kind: "sandbox", label: "lit du web arbitraire — prompt injection, à lancer en sandbox" },
  ],
};

const badgesFor = (path) =>
  BADGES[path] ?? BADGES[`${path.split("/")[0]}/*`] ?? [];

/** Human labels for the top-level folders, mirroring the root README. */
const CATEGORIES = {
  engineering: "Concevoir, écrire, relire du code et le découper en travail",
  productivity: "Durcir une idée, l'écrire, la dessiner, l'apprendre",
  kb: "Faire entrer du savoir dans une base lisible par agent",
  research: "Déléguer le travail de lecture",
  "agent-ops": "Configurer et cadrer les agents eux-mêmes",
  "windows&bash-tools": "Franchir la frontière WSL → Windows",
};

/** Files whose presence means the skill needs a setup step before it runs. */
const SETUP_HINTS = [
  ["pyproject.toml", "uv sync"],
  ["requirements.txt", "pip install -r requirements.txt"],
  ["package.json", "npm i"],
];

/**
 * The tracked files, straight from git.
 *
 * Deliberately not a filesystem walk. The index tells the CLI what to download
 * from GitHub, so it must describe what git actually has: a walk also picks up
 * ignored and untracked files — a stray `uv.lock` did exactly that — and every
 * user then gets a 404 on a file that only ever existed on one machine.
 *
 * `git ls-files -s` also carries the real mode, which is what GitHub serves, so
 * the executable bit no longer depends on the local umask.
 */
function trackedFiles() {
  let raw;
  try {
    raw = execFileSync("git", ["ls-files", "-s", "-z"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (err) {
    throw new Error(`impossible de lire l'index git (${err.message})`);
  }

  return raw
    .split("\0")
    .filter(Boolean)
    .map((entry) => {
      // "<mode> <sha> <stage>\t<path>"
      const tab = entry.indexOf("\t");
      const [mode] = entry.slice(0, tab).split(" ");
      return { path: entry.slice(tab + 1), mode };
    })
    .filter(({ path }) => {
      // Only directories are pruned, never files: `.skillignore` tells install-time
      // security scanners what to skip, so it has to ship with its skill.
      const dirs = path.split("/").slice(0, -1);
      // `.macos-original/` is a variant kept for reference, not an installable skill.
      return !dirs.some((seg) => seg.startsWith(".") || PRUNE.has(seg));
    });
}

/**
 * Reads the YAML frontmatter of a SKILL.md. Tolerates CRLF: at least one skill in
 * this repo round-tripped through Windows, and a lone `\r` on the `---` fence is
 * enough to make a naive parser see no frontmatter at all.
 */
async function frontmatter(file) {
  const raw = (await readFile(file, "utf8")).replace(/\r\n/g, "\n");
  const match = /^---\n([\s\S]*?)\n---(?:\n|$)/.exec(raw);
  if (!match) return null;
  try {
    return parseYaml(match[1]) ?? {};
  } catch (err) {
    throw new Error(`${relative(REPO_ROOT, file)}: invalid frontmatter — ${err.message}`);
  }
}

async function collect() {
  const skills = [];
  const problems = [];

  const tracked = trackedFiles();

  for (const entry of tracked) {
    if (!entry.path.endsWith("/SKILL.md")) continue;

    const path = entry.path.slice(0, -"/SKILL.md".length);
    const [category, ...rest] = path.split("/");

    const fm = await frontmatter(join(REPO_ROOT, entry.path));
    if (!fm) {
      problems.push(`${path}: no YAML frontmatter`);
      continue;
    }
    if (!fm.name) problems.push(`${path}: missing \`name\``);
    if (!fm.description) problems.push(`${path}: missing \`description\``);

    const folder = rest.at(-1) ?? category;
    if (fm.name && fm.name !== folder) {
      problems.push(`${path}: \`name: ${fm.name}\` does not match the folder \`${folder}\``);
    }

    const files = [];
    let bytes = 0;
    for (const file of tracked) {
      if (!file.path.startsWith(`${path}/`)) continue;
      let size;
      try {
        ({ size } = await stat(join(REPO_ROOT, file.path)));
      } catch {
        problems.push(`${file.path}: tracké par git mais absent du disque`);
        continue;
      }
      const record = { path: file.path.slice(path.length + 1), bytes: size };
      // raw.githubusercontent.com serves content without permissions, so the bit
      // travels in the index instead — otherwise every bundled launcher lands
      // non-executable and the skill breaks on first run.
      if (file.mode === "100755") record.exec = true;
      files.push(record);
      bytes += size;
    }
    files.sort((a, b) => a.path.localeCompare(b.path));

    const setup = SETUP_HINTS.find(([needle]) =>
      files.some((f) => f.path === needle || f.path.endsWith(`/${needle}`)),
    );

    skills.push({
      name: fm.name ?? folder,
      path,
      category,
      group: rest.length > 1 ? rest.slice(0, -1).join("/") : null,
      description: String(fm.description ?? "").trim(),
      argumentHint: fm["argument-hint"] ?? null,
      disableModelInvocation: fm["disable-model-invocation"] ?? null,
      allowedTools: fm["allowed-tools"] ?? null,
      license: fm.license ?? null,
      badges: badgesFor(path),
      setup: setup ? setup[1] : null,
      bytes,
      files,
    });
  }

  skills.sort((a, b) => a.path.localeCompare(b.path));
  return { skills, problems };
}

const { skills, problems } = await collect();

const duplicates = skills
  .map((s) => s.name)
  .filter((name, i, all) => all.indexOf(name) !== i);
for (const name of new Set(duplicates)) {
  problems.push(`\`${name}\` is used by several skills — install targets would collide`);
}

if (problems.length) {
  console.error("✖ index not written:");
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}

const categories = [...new Set(skills.map((s) => s.category))].map((id) => ({
  id,
  description: CATEGORIES[id] ?? null,
  count: skills.filter((s) => s.category === id).length,
}));

const index = {
  repo: REPO,
  ref: REF,
  version: 1,
  count: skills.length,
  categories,
  skills,
};

const serialized = `${JSON.stringify(index, null, 2)}\n`;

if (process.argv.includes("--check")) {
  const current = await readFile(OUT, "utf8").catch(() => null);
  if (current !== serialized) {
    console.error("✖ skills.json is stale — run `npm run index`");
    process.exit(1);
  }
  console.log(`✔ skills.json is up to date (${skills.length} skills)`);
} else {
  await writeFile(OUT, serialized);
  const total = skills.reduce((sum, s) => sum + s.bytes, 0);
  console.log(
    `✔ skills.json — ${skills.length} skills, ${categories.length} categories, ` +
      `${(total / 1e6).toFixed(1)} MB of payload indexed`,
  );
}
