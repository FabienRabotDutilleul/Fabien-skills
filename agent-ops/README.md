# agent-ops

Les skills méta : ceux qui configurent, cadrent et outillent les agents eux-mêmes plutôt qu'un
projet donné.

| Skill | Ce qu'il fait |
|---|---|
| `global-agent-guardrails` | **Le garde-fou.** Une denylist unique de commandes shell catastrophiques (`rm -rf` sur `/` ou `~`, `dd`/`mkfs`, `sudo rm`, fork bombs, `curl \| sh`, `git push --force`, `gh repo delete`) appliquée en hook PreToolUse / pre-exec sur *tous* les agents de la machine — Cursor, Claude Code, Codex, OpenCode, Pi, Hermes, Grok, Droid, Devin. À installer en premier sur une machine neuve. |
| `goal-loop` | Explique et rédige les instructions pour `/goal`, la boucle auto-vérifiante (plan → agis → teste → relis → itère). À prendre pour lancer un run autonome long ou pour faire écrire un bon prompt de goal. |
| `writing-for-agents` | La référence pour écrire tout document que lit un agent — un skill, un `AGENTS.md`/`CLAUDE.md`, une doc atteinte par un pointeur : le vocabulaire et les principes qui les rendent prévisibles. Sa mécanique propre aux skills (frontmatter, invocation, skills routeurs) est dans [`SKILL-MECHANICS.md`](writing-for-agents/SKILL-MECHANICS.md). **À lire avant d'ajouter quoi que ce soit à ce dépôt.** Seul skill du dossier invocable par l'agent lui-même. |
| `ask-me` | Le routeur : décris ta situation, il te dit quel skill ou quel enchaînement prendre — sur toute la collection (engineering, recherche, kb, productivité, outils machine). Le point d'entrée quand tu ne sais pas par où commencer. Il embarque [`PHASE-BOUNDARIES.md`](ask-me/PHASE-BOUNDARIES.md) : l'arbre de décision entre `continue`, `/clear`, `/handoff`, sous-agent et `/compact` à la frontière entre deux phases. |

## Ordre d'installation

> [!IMPORTANT]
> ### 🛑 `global-agent-guardrails` est **obligatoire chez Rabot Dutilleul**
>
> À installer **à la première utilisation**, avant tout autre skill. Aucun agent ne tourne sur
> une machine qui n'a pas le garde-fou.

1. 🛑 **`global-agent-guardrails`** — avant tout le reste, une fois par machine.
2. ⚙️ [`engineering/setup-matt-pocock-skills`](../engineering/) — une fois par dépôt qui utilisera `engineering/`.
3. ✅ Le reste au besoin.

## Attribution

`writing-for-agents` vient du set de skills de **Matt Pocock**. `ask-me` en dérive
(ex-`ask-matt`), généralisé pour router sur toute la collection.
