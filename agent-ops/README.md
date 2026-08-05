# agent-ops

Les skills méta : ceux qui configurent, cadrent et outillent les agents eux-mêmes plutôt qu'un
projet donné.

| Skill | Ce qu'il fait |
|---|---|
| `global-agent-guardrails` | **Le garde-fou.** Une denylist unique de commandes shell catastrophiques (`rm -rf` sur `/` ou `~`, `dd`/`mkfs`, `sudo rm`, fork bombs, `curl \| sh`, `git push --force`, `gh repo delete`) appliquée en hook PreToolUse / pre-exec sur *tous* les agents de la machine — Cursor, Claude Code, Codex, OpenCode, Pi, Hermes, Grok, Droid, Devin. À installer en premier sur une machine neuve. |
| `goal-loop` | Explique et rédige les instructions pour `/goal`, la boucle auto-vérifiante (plan → agis → teste → relis → itère). À prendre pour lancer un run autonome long ou pour faire écrire un bon prompt de goal. |
| `writing-great-skills` | La référence pour écrire et éditer des skills : le vocabulaire et les principes qui rendent un skill prévisible. **À lire avant d'ajouter quoi que ce soit à ce dépôt.** |
| `setup-help` | Guide pas à pas n'importe quelle installation. Sa particularité : une seule étape à la fois, suivie systématiquement de la liste de toutes les étapes restantes. |
| `setup-matt-pocock-skills` | Configure un dépôt pour accueillir les skills d'`engineering/` : tracker d'issues, vocabulaire de labels de triage, layout des docs de domaine. À lancer une fois, avant le premier usage des autres. |
| `ask-matt` | Le routeur : décrit ta situation, il te dit quel skill ou quel enchaînement prendre. Le point d'entrée quand tu ne sais pas par où commencer. |

## Ordre d'installation recommandé

1. `global-agent-guardrails` — avant tout le reste, sur une machine neuve.
2. `setup-matt-pocock-skills` — une fois par dépôt qui utilisera `engineering/`.
3. Le reste au besoin.

## Attribution

`ask-matt`, `setup-matt-pocock-skills` et `writing-great-skills` viennent du set de skills de
**Matt Pocock**.
