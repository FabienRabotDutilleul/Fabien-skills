/**
 * `npx add-fabien-skills` — pick skills from the Fabien-skills collection and drop
 * them where Claude Code will find them.
 */
import { loadIndex, isSourceError, DEFAULT_REF, DEFAULT_REPO } from "./registry.mjs";
import { installSkill, targetDir, existsAt, sweepPartials } from "./install.mjs";
import { multiselect, select, CANCEL } from "./prompts.mjs";
import { c, s, accent, intro, outro, cancel, note, write, writeErr, columns, truncate, clearLine, BADGES } from "./ui.mjs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { createRequire } from "node:module";

// `createRequire` rather than `import ... with { type: "json" }`: import attributes
// are a parse error before Node 20.10, which would crash the CLI before the version
// guard in bin/ ever got the chance to explain why.
const { version } = createRequire(import.meta.url)("../package.json");

const HELP = `
${accent("add-fabien-skills")} — installe les skills de ${c.bold("Fabien-skills")} dans Claude Code

${c.bold("USAGE")}
  npx add-fabien-skills [options]

${c.bold("OPTIONS")}
  -s, --skills <a,b,c>   non interactif : skills à installer (nom, ou "all")
  -t, --target <where>   ${c.gray("global")} → ~/.claude/skills   ${c.gray("local")} → ./.claude/skills
  -d, --dmi <bool>       valeur de disable-model-invocation (défaut : celle du dépôt)
  -f, --force            écrase sans demander
  -l, --list             liste les skills disponibles puis sort
  -n, --dry-run          montre le plan, n'écrit rien
  -y, --yes              accepte les réponses par défaut sans demander
      --no-interactive   n'ouvre aucun prompt (déduit du terminal par défaut)
      --ref <ref>        branche ou tag du dépôt (défaut : ${DEFAULT_REF})
      --source <path>    lit un dépôt local au lieu de GitHub
  -h, --help             cette aide
  -v, --version          la version de cet outil

${c.bold("EXEMPLES")}
  npx add-fabien-skills
  npx add-fabien-skills -s tdd,code-review -t local
  npx add-fabien-skills -s all -t global --force
`;

function parseArgs(argv) {
  // Answered before the line is validated: someone who mistyped a flag is exactly
  // who needs the help text, and refusing it to teach them a lesson helps nobody.
  if (argv.includes("-h") || argv.includes("--help")) return { help: true };
  if (argv.includes("-v") || argv.includes("--version")) return { version: true };

  const opts = { force: false, list: false, dryRun: false, ref: DEFAULT_REF };
  const rest = [...argv];
  while (rest.length) {
    const arg = rest.shift();
    switch (arg) {
      case "-s": case "--skills": opts.skills = rest.shift(); break;
      case "-t": case "--target": opts.target = rest.shift(); break;
      case "-d": case "--dmi": case "--disable-model-invocation": opts.dmi = rest.shift(); break;
      case "--ref": opts.ref = rest.shift(); break;
      case "--source": opts.source = rest.shift(); break;
      case "-f": case "--force": opts.force = true; break;
      case "-l": case "--list": opts.list = true; break;
      case "-n": case "--dry-run": opts.dryRun = true; break;
      case "-y": case "--yes": opts.yes = true; break;
      case "--interactive": opts.interactive = true; break;
      case "--no-interactive": opts.interactive = false; break;
      case "-h": case "--help": opts.help = true; break;
      case "-v": case "--version": opts.version = true; break;
      default:
        if (arg.startsWith("-")) throw new UserError(`option inconnue : ${arg}`);
        opts.source ??= arg;
    }
  }
  if (opts.target && !["global", "local"].includes(opts.target)) {
    throw new UserError("--target doit être 'global' ou 'local'");
  }
  if (opts.dmi !== undefined && !["true", "false"].includes(opts.dmi)) {
    throw new UserError("--dmi doit être 'true' ou 'false'");
  }
  return opts;
}

class UserError extends Error {}

const tilde = (path) => (path.startsWith(homedir()) ? path.replace(homedir(), "~") : path);
const prettySize = (bytes) =>
  bytes >= 1e6 ? `${(bytes / 1e6).toFixed(1)} Mo` : `${Math.max(1, Math.round(bytes / 1e3))} Ko`;

async function spin(label, task) {
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  if (!process.stdout.isTTY) return task();
  let i = 0;
  write(`${c.gray(s.bar)}  ${accent(frames[0])} ${label}`);
  const timer = setInterval(() => {
    i += 1;
    write(`\r${c.gray(s.bar)}  ${accent(frames[i % frames.length])} ${label}`);
  }, 80);
  try {
    return await task();
  } finally {
    clearInterval(timer);
    clearLine();
  }
}

function listSkills(index) {
  let category = null;
  for (const skill of index.skills) {
    if (skill.category !== category) {
      category = skill.category;
      write(`\n${c.bold(category)}\n`);
    }
    const tags = (skill.badges ?? [])
      .map((b) => BADGES[b.kind])
      .filter(Boolean)
      .map((b) => b.color(`${b.icon} ${b.label}`))
      .join(" ");
    write(truncate(`  ${skill.name.padEnd(28)} ${c.gray(skill.description)} ${tags}`, columns()) + "\n");
  }
  write(`\n${c.gray(`${index.skills.length} skills`)}\n`);
}

function resolveRequested(index, spec) {
  if (spec.trim() === "all") return index.skills;
  const wanted = spec.split(",").map((x) => x.trim()).filter(Boolean);
  return wanted.map((name) => {
    const hit = index.skills.find((skill) => skill.name === name || skill.path === name);
    if (!hit) throw new UserError(`skill inconnu : ${name} ${c.gray("(essaie --list)")}`);
    return hit;
  });
}

export async function run(argv) {
  const opts = parseArgs(argv);

  // Answered before anything else, so `--help --bogus` still helps and neither
  // touches the network. `create-vite --version` scaffolds a project instead;
  // `create-astro --version` creates a directory called "--version".
  if (opts.help) {
    write(HELP);
    return 0;
  }
  if (opts.version) {
    write(`${version}\n`);
    return 0;
  }

  const interactive = opts.interactive ?? (process.stdin.isTTY && process.stdout.isTTY);
  // `--yes` means "stop asking me the secondary questions". It never implies
  // --force: overwriting someone's edited skill stays an explicit decision.
  const ask = interactive && !opts.yes;

  const isLocalSource = opts.source && (opts.source.startsWith(".") || opts.source.startsWith("/"));
  // The banner is decoration; it must not end up in `--list > skills.txt`.
  if (!opts.list) {
    intro(
      "add-fabien-skills",
      isLocalSource
        ? `local · ${tilde(resolve(opts.source))}`
        : `${opts.source ?? DEFAULT_REPO}${opts.ref === DEFAULT_REF ? "" : `#${opts.ref}`}`,
    );
  }

  const index = await spin("lecture de l'index…", () =>
    loadIndex({ source: opts.source, ref: opts.ref }),
  );

  if (opts.list) {
    listSkills(index);
    return 0;
  }

  // ---- 1. which skills -----------------------------------------------------
  let chosen;
  if (opts.skills) {
    chosen = resolveRequested(index, opts.skills);
  } else if (interactive) {
    const picked = await multiselect({ title: "Quels skills installer ?", skills: index.skills });
    if (picked === CANCEL) {
      cancel("annulé");
      return 130;
    }
    chosen = index.skills.filter((skill) => picked.includes(skill.name));
  } else {
    throw new UserError("pas de terminal interactif — utilise --skills (voir --help)");
  }

  if (chosen.length === 0) {
    outro(c.gray("rien de sélectionné — à bientôt"));
    return 0;
  }

  note(`${c.green(s.tick)} ${c.bold(chosen.length)} skill${chosen.length > 1 ? "s" : ""} ${c.gray(`· ${prettySize(chosen.reduce((n, x) => n + x.bytes, 0))}`)}`);

  // ---- 2. where ------------------------------------------------------------
  let target = opts.target;
  if (!target) {
    if (!ask) target = "global";
    else {
      const picked = await select({
        title: "Installer où ?",
        options: [
          { value: "global", label: "global", hint: `${tilde(targetDir("global"))}  — tous tes projets` },
          { value: "local", label: "local", hint: `./.claude/skills  — ce projet seulement` },
        ],
      });
      if (picked === CANCEL) {
        cancel("annulé");
        return 130;
      }
      target = picked;
    }
  }
  const dir = targetDir(target);

  // ---- 3. model invocation -------------------------------------------------
  let dmi = opts.dmi === undefined ? undefined : opts.dmi === "true";
  if (dmi === undefined) {
    if (!ask) dmi = null;
    else {
      const picked = await select({
        title: "L'agent peut-il déclencher ces skills tout seul ?",
        options: [
          { value: null, label: "garder le réglage du dépôt", hint: "recommandé" },
          { value: true, label: "non, manuel uniquement", hint: "disable-model-invocation: true — /nom-du-skill" },
          { value: false, label: "oui, il peut les déclencher", hint: "disable-model-invocation: false" },
        ],
      });
      if (picked === CANCEL) {
        cancel("annulé");
        return 130;
      }
      dmi = picked;
    }
  }

  // ---- 4. plan -------------------------------------------------------------
  const existing = [];
  for (const skill of chosen) {
    if (await existsAt(dir, skill.name)) existing.push(skill);
  }

  write(`${c.gray(s.bar)}  ${c.bold("Plan")}  ${c.gray(`${s.arrow} ${tilde(dir)}`)}\n`);
  for (const skill of chosen) {
    const mark = existing.includes(skill) ? c.yellow("~") : c.green("+");
    const suffix = existing.includes(skill) ? c.yellow("  (déjà là)") : "";
    write(`${c.gray(s.bar)}    ${mark} ${skill.name}${c.gray(`  ${skill.path}`)}${suffix}\n`);
  }
  // Everything the user should know before the files land: what a skill costs,
  // what it needs, and which ones read untrusted web content.
  const caveats = [];
  for (const skill of chosen) {
    for (const badge of skill.badges ?? []) {
      caveats.push(`${c.bold(skill.name)} ${c.gray(badge.label)}`);
    }
    if (skill.setup) {
      caveats.push(`${c.bold(skill.name)} ${c.gray(`demande \`${skill.setup}\` avant de tourner`)}`);
    }
  }
  if (caveats.length) {
    write(`${c.gray(s.bar)}\n`);
    for (const caveat of caveats) {
      write(truncate(`${c.gray(s.bar)}  ${c.yellow(s.warn)} ${caveat}`, columns()) + "\n");
    }
  }
  write(`${c.gray(s.bar)}\n`);

  if (opts.dryRun) {
    outro(c.gray("dry run — rien écrit"));
    return 0;
  }

  if (existing.length && !opts.force) {
    if (!ask) {
      throw new UserError(
        `${existing.map((x) => x.name).join(", ")} ${existing.length > 1 ? "existent" : "existe"} déjà — utilise --force`,
      );
    }
    const picked = await select({
      title: `${existing.length} skill${existing.length > 1 ? "s" : ""} déjà installé${existing.length > 1 ? "s" : ""} — on fait quoi ?`,
      options: [
        { value: "overwrite", label: "écraser", hint: "remplace la version installée" },
        { value: "skip", label: "les ignorer", hint: "n'installe que les nouveaux" },
        { value: "abort", label: "annuler", hint: "" },
      ],
    });
    if (picked === CANCEL || picked === "abort") {
      cancel("annulé");
      return 130;
    }
    if (picked === "skip") chosen = chosen.filter((skill) => !existing.includes(skill));
  }

  if (chosen.length === 0) {
    outro(c.gray("rien à faire"));
    return 0;
  }

  // ---- 5. install ----------------------------------------------------------
  // A run killed mid-download leaves its staging behind; clear any before adding
  // more, so the target never accumulates `.name.partial` folders.
  await sweepPartials(dir);

  const failures = [];
  for (const skill of chosen) {
    try {
      const { written } = await spin(`${skill.name}${c.gray(` · ${skill.files.length} fichiers`)}`, () =>
        installSkill(index, skill, dir, { dmi: dmi ?? null }),
      );
      write(`${c.gray(s.bar)}  ${c.green(s.tick)} ${c.bold(skill.name)} ${c.gray(`${written} fichier${written > 1 ? "s" : ""}`)}\n`);
    } catch (err) {
      failures.push({ skill, err });
      write(`${c.gray(s.bar)}  ${c.red(s.cross)} ${c.bold(skill.name)} ${c.red(err.message)}\n`);
    }
  }

  const installed = chosen.length - failures.length;
  write(`${c.gray(s.bar)}\n`);

  if (installed > 0) {
    write(`${c.gray(s.bar)}  ${c.gray("Redémarre Claude Code, puis")} ${accent(`/${chosen.find((x) => !failures.some((f) => f.skill === x))?.name}`)}\n`);
    write(`${c.gray(s.bar)}\n`);
  }

  outro(
    failures.length
      ? `${c.green(`${installed} installé${installed > 1 ? "s" : ""}`)}, ${c.red(`${failures.length} en échec`)}`
      : c.green(`${installed} skill${installed > 1 ? "s" : ""} installé${installed > 1 ? "s" : ""} ${s.arrow} ${tilde(dir)}`),
  );

  return failures.length ? 1 : 0;
}

export async function main(argv) {
  try {
    return await run(argv);
  } catch (err) {
    if (err instanceof UserError || isSourceError(err)) {
      writeErr(`${c.gray(s.bar)}\n${c.red(s.cross)}  ${err.message}\n\n`);
      return 1;
    }
    throw err;
  }
}
