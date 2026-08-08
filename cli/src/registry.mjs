/**
 * Where skills come from.
 *
 * The CLI never clones. It reads `skills.json` — one ~12 KB gzipped request — and
 * then fetches only the files of the skills that were picked. The repo tarball is
 * ~16 MB, nearly all of it media belonging to a single skill, so cloning to install
 * a 7 KB skill would be the slowest possible way to do this.
 *
 * Two transports, in this order:
 *   - raw.githubusercontent.com, always, unauthenticated — a CDN, and the only
 *     path that scales to a 143-file skill
 *   - the contents API with GITHUB_TOKEN / GH_TOKEN, but only after raw returns
 *     404 and only if a token exists, i.e. only for a genuinely private repo
 *
 * The order matters. Preferring the API whenever a token happened to be exported
 * pushed every `gh` user, every devcontainer and every CI job off the CDN and onto
 * a 5000/h budget — one call per file — while raw ignores credentials entirely.
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

/** Transient by nature: worth another go, unlike a 404 or a 401. */
const RETRYABLE = new Set([408, 425, 429, 500, 502, 503, 504]);

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/**
 * Native fetch throws a bare `TypeError: fetch failed` and buries the real reason
 * in `cause`, so "impossible de joindre GitHub (fetch failed)" told the user
 * nothing. This surfaces ENOTFOUND / ECONNREFUSED / EAI_AGAIN / CERT_HAS_EXPIRED.
 */
const causeOf = (err) => err?.cause?.errors?.[0]?.code ?? err?.cause?.code ?? err?.message;

/** Node ignores HTTPS_PROXY unless told to, which looks exactly like "no network". */
const proxyHint = () =>
  process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy
    ? "\n  Un proxy est configuré, mais Node ne le suit pas de lui-même :\n" +
      "  relance avec NODE_USE_ENV_PROXY=1 (Node >= 22.21)."
    : "";

/** Honours `Retry-After` when GitHub sends one, exponential backoff otherwise. */
function backoff(response, attempt) {
  const after = Number(response.headers.get("retry-after"));
  if (Number.isFinite(after) && after > 0) return Math.min(after * 1000, 10_000);
  return 300 * 2 ** attempt + Math.random() * 200;
}

/**
 * One request, retried on transient failures.
 *
 * `raw.githubusercontent.com` carries an anti-scraping throttle that answers 429
 * with no warning and no `x-ratelimit-*` headers, and a big skill is exactly the
 * burst that trips it. Without this, one blip killed the whole install.
 */
async function get(url, { accept, timeout, auth = null, attempts = 3 }) {
  let failure;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(timeout),
        headers: {
          accept,
          "user-agent": "add-fabien-skills",
          ...(auth ? { authorization: `Bearer ${auth}` } : {}),
        },
      });
      if (!RETRYABLE.has(response.status) || attempt === attempts - 1) return response;
      await sleep(backoff(response, attempt));
    } catch (err) {
      failure = err;
      // A timeout already waited the full budget; retrying just triples the wait.
      if (err.name === "TimeoutError" || attempt === attempts - 1) break;
      await sleep(300 * 2 ** attempt + Math.random() * 200);
    }
  }
  throw new SourceError(
    failure?.name === "TimeoutError"
      ? "la requête a expiré — réseau lent ou coupé ?"
      : `impossible de joindre GitHub (${causeOf(failure)})${proxyHint()}`,
  );
}

/** The private-repo path: authenticated, one API call per file, no CDN. */
async function fetchViaApi(repo, ref, path, timeout) {
  const response = await get(apiUrl(repo, ref, path), {
    accept: "application/vnd.github.raw",
    timeout,
    auth: token(),
  });
  if (response.ok) return Buffer.from(await response.arrayBuffer());
  if (response.status === 404) throw new SourceError(`introuvable : ${path}`);
  if (response.status === 401 || response.status === 403) {
    throw new SourceError(`accès refusé sur ${repo} — le token porte-t-il \`contents:read\` ?`);
  }
  throw new SourceError(`GitHub a répondu ${response.status} sur ${path}`);
}

/** Fetches one repo path as bytes. */
async function fetchPath(repo, ref, path, { timeout = 30_000 } = {}) {
  // Never send credentials here: raw ignores them, and `vary: Authorization` means
  // sending one only carves out a private CDN cache key that nobody else can hit.
  const response = await get(rawUrl(repo, ref, path), { accept: "*/*", timeout });
  if (response.ok) return Buffer.from(await response.arrayBuffer());

  if (response.status === 404) {
    if (token()) return fetchViaApi(repo, ref, path, timeout);
    throw new SourceError(`introuvable : ${path}`);
  }
  if (response.status === 429) {
    throw new SourceError(
      `GitHub throttle les téléchargements depuis cette IP (429 sur ${path}).\n` +
        "  Réessaie dans quelques minutes, ou installe moins de skills à la fois.",
    );
  }
  throw new SourceError(`GitHub a répondu ${response.status} sur ${path}`);
}

/**
 * Tells apart "the index is missing" from "the repo is private" from "this IP is
 * rate-limited". All three surface as a 404 on the file, and the fixes have
 * nothing in common — so the answer has to come from the status, not from the
 * mere fact that the probe failed.
 */
async function diagnose404(repo, ref) {
  let response;
  try {
    response = await get(`https://api.github.com/repos/${repo}`, {
      accept: "application/vnd.github+json",
      timeout: 10_000,
      auth: token(),
      attempts: 1,
    });
  } catch {
    return `pas de skills.json sur ${repo}#${ref}, et l'API GitHub est injoignable pour dire pourquoi.`;
  }

  if (response.ok) {
    return (
      `pas de skills.json sur ${repo}#${ref} — la branche existe-t-elle, ` +
      "et l'index y est-il poussé (`npm run index` puis commit) ?"
    );
  }

  // The API allows 60 requests per hour per IP unauthenticated. Behind corporate
  // egress or shared NAT that is spent by somebody else, and reading it as
  // "the repo is private" sends the user chasing a permission problem they
  // do not have.
  if (response.status === 403 || response.status === 429) {
    const reset = Number(response.headers.get("x-ratelimit-reset"));
    const when = Number.isFinite(reset) && reset > 0
      ? ` Réessaie après ${new Date(reset * 1000).toLocaleTimeString()}.`
      : "";
    return (
      `GitHub limite les requêtes venant de cette IP (60/h sans token).${when}\n` +
      "  Ou donne-lui un token :  export GITHUB_TOKEN=$(gh auth token)"
    );
  }

  if (response.status === 401) {
    return `le token GITHUB_TOKEN/GH_TOKEN est refusé par GitHub (401) — expiré ?`;
  }

  if (response.status === 404) {
    return token()
      ? `${repo} est inaccessible avec ce token — porte-t-il \`contents:read\` sur ce dépôt ?`
      : `${repo} est privé (ou n'existe pas).\n` +
        "  Rends le dépôt public pour que `npx add-fabien-skills` marche pour tout le monde,\n" +
        "  ou exporte un token GitHub :  export GITHUB_TOKEN=$(gh auth token)";
  }

  return `${repo}#${ref} : GitHub a répondu ${response.status}, impossible de diagnostiquer.`;
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
