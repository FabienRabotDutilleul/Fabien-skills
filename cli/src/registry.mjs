/**
 * Where skills come from.
 *
 * The CLI never clones. It reads `skills.json` — one ~12 KB gzipped request — and
 * then fetches only the files of the skills that were picked. The repo tarball is
 * ~16 MB, nearly all of it media belonging to a single skill, so cloning to install
 * a 7 KB skill would be the slowest possible way to do this.
 */
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";

export const DEFAULT_REPO = "FabienRabotDutilleul/Fabien-skills";
export const DEFAULT_REF = "main";

/** `windows&bash-tools` is a real folder here, so segments must be encoded. */
const encodePath = (path) => path.split("/").map(encodeURIComponent).join("/");

export const rawUrl = (repo, ref, path) =>
  `https://raw.githubusercontent.com/${repo}/${encodeURIComponent(ref)}/${encodePath(path)}`;

class SourceError extends Error {}
export const isSourceError = (err) => err instanceof SourceError;

async function getJson(url, { timeout = 15_000 } = {}) {
  let response;
  try {
    response = await fetch(url, {
      signal: AbortSignal.timeout(timeout),
      headers: { accept: "application/json" },
    });
  } catch (err) {
    throw new SourceError(
      err.name === "TimeoutError"
        ? "la requête a expiré — réseau lent ou coupé ?"
        : `impossible de joindre GitHub (${err.message})`,
    );
  }
  if (response.status === 404) {
    throw new SourceError(`introuvable : ${url}`);
  }
  if (!response.ok) {
    throw new SourceError(`GitHub a répondu ${response.status} sur ${url}`);
  }
  return response.json();
}

function validate(index) {
  if (!index || !Array.isArray(index.skills) || index.skills.length === 0) {
    throw new SourceError("l'index est vide ou mal formé");
  }
  return index;
}

/**
 * Loads the index. A local path is accepted so the repo can be tested before the
 * index is pushed; anything else is read from GitHub.
 */
export async function loadIndex({ source, repo = DEFAULT_REPO, ref = DEFAULT_REF } = {}) {
  if (source && (isAbsolute(source) || source.startsWith("."))) {
    const path = resolve(source, "skills.json");
    let raw;
    try {
      raw = await readFile(path, "utf8");
    } catch {
      throw new SourceError(
        `pas de skills.json dans ${source} — lance \`npm run index\` dans le dépôt`,
      );
    }
    const index = validate(JSON.parse(raw));
    return { ...index, origin: { kind: "local", root: resolve(source) } };
  }

  const activeRepo = source ?? repo;
  let raw;
  try {
    raw = await getJson(rawUrl(activeRepo, ref, "skills.json"));
  } catch (err) {
    if (isSourceError(err) && err.message.startsWith("introuvable")) {
      throw new SourceError(
        `pas de skills.json sur ${activeRepo}#${ref} — la branche existe-t-elle, et l'index y est-il poussé ?`,
      );
    }
    throw err;
  }
  const index = validate(raw);
  return { ...index, origin: { kind: "github", repo: activeRepo, ref } };
}

/** Resolves the bytes of one file of one skill, wherever the index came from. */
export async function readSkillFile(index, skill, file) {
  if (index.origin.kind === "local") {
    return readFile(resolve(index.origin.root, skill.path, file.path));
  }
  const url = rawUrl(index.origin.repo, index.origin.ref, `${skill.path}/${file.path}`);
  const response = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!response.ok) {
    throw new SourceError(`${skill.name}/${file.path} — GitHub a répondu ${response.status}`);
  }
  return Buffer.from(await response.arrayBuffer());
}
