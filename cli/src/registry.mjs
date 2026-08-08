/**
 * Where skills come from.
 *
 * The CLI never clones. It reads `skills.json` — one ~12 KB gzipped request — and
 * then fetches only the files of the skills that were picked. The repo tarball is
 * ~16 MB, nearly all of it media belonging to a single skill, so cloning to install
 * a 7 KB skill would be the slowest possible way to do this.
 *
 * Two transports, picked automatically:
 *   - public repo  → raw.githubusercontent.com, no auth, no rate limit worth caring about
 *   - private repo → the contents API with a token from GITHUB_TOKEN / GH_TOKEN
 */
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";

export const DEFAULT_REPO = "FabienRabotDutilleul/Fabien-skills";
export const DEFAULT_REF = "main";

export const token = () => process.env.GITHUB_TOKEN || process.env.GH_TOKEN || null;

/** `windows&bash-tools` is a real folder here, so segments must be encoded. */
const encodePath = (path) => path.split("/").map(encodeURIComponent).join("/");

export const rawUrl = (repo, ref, path) =>
  `https://raw.githubusercontent.com/${repo}/${encodeURIComponent(ref)}/${encodePath(path)}`;

/** The contents API serves private blobs; `.raw` returns bytes, not JSON. */
export const apiUrl = (repo, ref, path) =>
  `https://api.github.com/repos/${repo}/contents/${encodePath(path)}?ref=${encodeURIComponent(ref)}`;

class SourceError extends Error {}
export const isSourceError = (err) => err instanceof SourceError;

const headers = (accept) => {
  const auth = token();
  return {
    accept,
    "user-agent": "add-fabien-skills",
    ...(auth ? { authorization: `Bearer ${auth}` } : {}),
  };
};

async function get(url, accept, timeout) {
  let response;
  try {
    response = await fetch(url, { signal: AbortSignal.timeout(timeout), headers: headers(accept) });
  } catch (err) {
    throw new SourceError(
      err.name === "TimeoutError"
        ? "la requête a expiré — réseau lent ou coupé ?"
        : `impossible de joindre GitHub (${err.message})`,
    );
  }
  return response;
}

/** Fetches one repo path as bytes, over whichever transport is available. */
async function fetchPath(repo, ref, path, { timeout = 30_000 } = {}) {
  const auth = token();
  const url = auth ? apiUrl(repo, ref, path) : rawUrl(repo, ref, path);
  const response = await get(url, auth ? "application/vnd.github.raw" : "*/*", timeout);

  if (response.status === 404) throw new SourceError(`introuvable : ${path}`);
  if (response.status === 403 || response.status === 401) {
    throw new SourceError(
      auth
        ? `accès refusé sur ${repo} — le token n'a pas le droit \`contents:read\` ?`
        : `accès refusé sur ${repo} (${response.status})`,
    );
  }
  if (!response.ok) throw new SourceError(`GitHub a répondu ${response.status} sur ${path}`);

  return Buffer.from(await response.arrayBuffer());
}

/**
 * Tells apart "the index is missing" from "the repo is private or does not exist".
 * Both surface as a 404 on the file, and the fix is completely different.
 */
async function diagnose404(repo, ref) {
  const response = await get(`https://api.github.com/repos/${repo}`, "application/vnd.github+json", 10_000);
  if (response.ok) {
    return (
      `pas de skills.json sur ${repo}#${ref} — la branche existe-t-elle, ` +
      "et l'index y est-il poussé (`npm run index` puis commit) ?"
    );
  }
  if (token()) {
    return `${repo} est inaccessible avec ce token — vérifie qu'il porte le droit \`contents:read\` sur ce dépôt.`;
  }
  return (
    `${repo} est privé (ou n'existe pas).\n` +
    "  Rends le dépôt public pour que `npx add-fabien-skills` marche pour tout le monde,\n" +
    "  ou exporte un token GitHub :  export GITHUB_TOKEN=$(gh auth token)"
  );
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
  let bytes;
  try {
    bytes = await fetchPath(activeRepo, ref, "skills.json", { timeout: 15_000 });
  } catch (err) {
    if (isSourceError(err) && err.message.startsWith("introuvable")) {
      throw new SourceError(await diagnose404(activeRepo, ref));
    }
    throw err;
  }

  let parsed;
  try {
    parsed = JSON.parse(bytes.toString("utf8"));
  } catch {
    throw new SourceError(`skills.json de ${activeRepo}#${ref} n'est pas du JSON valide`);
  }

  const index = validate(parsed);
  return { ...index, origin: { kind: "github", repo: activeRepo, ref } };
}

/** Resolves the bytes of one file of one skill, wherever the index came from. */
export async function readSkillFile(index, skill, file) {
  if (index.origin.kind === "local") {
    return readFile(resolve(index.origin.root, skill.path, file.path));
  }
  return fetchPath(index.origin.repo, index.origin.ref, `${skill.path}/${file.path}`);
}
