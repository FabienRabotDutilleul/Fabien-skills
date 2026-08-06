# Fabien-skills

Ma collection de skills pour Claude Code : 48 skills rangés par usage plutôt que par ordre
d'arrivée. Chaque dossier principal porte son propre README qui explique brièvement ce que fait
chacun de ses skills.

## Les six familles

| Dossier | Ce qu'on y trouve | Nb |
|---|---|---|
| [`engineering/`](engineering/) | Concevoir, écrire, relire du code et le découper en travail | 15 |
| [`productivity/`](productivity/) | Durcir une idée, l'écrire, la dessiner, l'apprendre | 13 |
| [`kb/`](kb/) | Faire entrer du savoir dans une base lisible par agent | 10 |
| [`research/`](research/) | Déléguer le travail de lecture | 3 |
| [`agent-ops/`](agent-ops/) | Configurer et cadrer les agents eux-mêmes | 6 |
| [`windows&bash-tools/`](windows&bash-tools/) | Franchir la frontière WSL → Windows | 1 + scripts |

---

# 🚦 Par où commencer

## 🛑 Étape 0 — obligatoire chez Rabot Dutilleul

> [!IMPORTANT]
> ### `agent-ops/global-agent-guardrails` s'installe **à la première utilisation**, avant tout le reste.
>
> Ce n'est pas une recommandation : chez Rabot Dutilleul, **aucun agent ne tourne sur une
> machine qui n'a pas le garde-fou installé.**
>
> Il pose une denylist unique de commandes shell catastrophiques — `rm -rf` sur `/` ou `~`,
> `dd`/`mkfs`, `sudo rm`, fork bombs, `curl | sh`, `git push --force`, `gh repo delete` — en
> hook PreToolUse / pre-exec sur **tous** les agents de la machine, pas seulement Claude Code. Execute:
>
> ```bash
> /global-agent-guardrails
> ```
>
> Ou demande à l'agent : *« installe global-agent-guardrails »*. Il fait le reste.
>
> ⏱️ Deux minutes. À faire **une seule fois par machine**, jamais par projet.

## ✅ Ensuite, selon ton besoin

| Tu veux… | Va voir |
|---|---|
| 🧭 **savoir quel skill prendre** | `agent-ops/ask-me` — un routeur sur toute la collection |
| ✍️ **en écrire un** | `agent-ops/writing-for-agents` — le vocabulaire et les principes |
| 🏗️ **bosser sur du code** | `agent-ops/setup-matt-pocock-skills` d'abord, une fois par dépôt |
| 😴 **qu'un run long ne soit pas coupé par un veille de Windows** | `windows&bash-tools/` |

---

## Installation

Un skill est un dossier contenant un `SKILL.md`. Pour l'activer, il faut qu'il soit visible
depuis `~/.claude/skills/` (global, disponible partout) ou `<projet>/.claude/skills/` (local au
projet). Le plus simple est de symlinker plutôt que copier — les mises à jour du dépôt suivent
toutes seules :

```bash
git clone https://github.com/FabienRabotDutilleul/Fabien-skills.git ~/dev/Fabien-skills

# un skill en global
ln -s ~/dev/Fabien-skills/engineering/tdd ~/.claude/skills/tdd

# un skill sur un projet précis
ln -s ~/dev/Fabien-skills/kb/ingest/ingest_xlsx <projet>/.claude/skills/ingest_xlsx
```

Certains skills embarquent des scripts avec leurs propres dépendances (`uv sync`, `npm i`) —
c'est signalé dans le README du dossier concerné.

## Avant d'installer

### Ceux qui coûtent de l'argent

- **`kb/youtube/watch`** — coûte de l'argent (clé API Whisper) et beaucoup de tokens. Il a son
  [propre README](kb/youtube/watch/README.md) avec l'avertissement détaillé.
- **`kb/youtube/channel-to-kb-supadata`** — s'appuie sur une API managée payante ; les deux
  autres variantes `channel-to-kb*` font la même chose gratuitement.

Ces skills n'existent que parce que certaines informations de veille sur le dev et l'IA se trouvent d'abord sur Youtube, hors on a pas toujours le temps de regarder une conférence de 2h, ces skills résolvent ce problème.

### Ceux qui se lancent en sandbox

> [!WARNING]
> **Les trois skills de [`research/`](research/) lisent du contenu web arbitraire et le
> ramènent dans le contexte de l'agent. C'est un vecteur de prompt injection.**
>
> Une page, un post ou un commentaire peut contenir des instructions déguisées que l'agent
> exécutera comme si elles venaient de toi. Ces skills se lancent **dans une sandbox** — dépôt
> jetable ou conteneur, sans credentials, sans accès au reste de ta machine — et jamais sur un
> projet qui contient des secrets.

- **`research/research`** — enquête sur des sources primaires et écrit le résultat dans le
  dépôt. Le plus sobre, mais il lit quand même du web non fiable.
- **`research/storm-research`** — quatre phases, cinq lentilles d'experts, peer review
  adversarial. Beaucoup de pages lues, donc beaucoup de surface d'injection.
- **`research/last30days`** — le plus exposé : il moissonne Reddit, X, YouTube, TikTok, Hacker
  News et GitHub, c'est-à-dire du texte écrit par n'importe qui. À ne jamais lancer hors bac à
  sable.

## Attribution

Cette collection agrège du travail qui n'est pas tout de moi :

| Origine | Skills |
|---|---|
| [Matt Pocock](https://github.com/mattpocock) | l'essentiel d'`engineering/`, plus `setup-matt-pocock-skills`, `writing-for-agents`, `to-questionnaire`, `wait-what`, la famille `grill*`, et `ask-me` (dérivé de son `ask-matt`) |
| [Cole Medin](https://github.com/coleam00) | les trois `channel-to-kb*` |
| [bradautomates](https://github.com/bradautomates/claude-video) — MIT | `watch` |

Les skills tiers sont republiés tels quels, non modifiés. Si tu es l'auteur de l'un d'eux et
que tu préfères un lien à une copie, ouvre une issue — je bascule sans discuter.

## Contexte métier

Quelques skills portent encore du contexte spécifique à mes projets et ne s'utiliseront pas
tels quels ailleurs : `quiz`, `classify_output`,
`inject_into_knowledge_base`. Ils restent publiés parce que la mécanique est réutilisable même
si le domaine ne l'est pas.

## Continuer de votre côté :


 - Les skills sont les nouvelles fonctionnalités des applications de nos jours. Il est fortement conseillé de tester et de créer vos skills vous-même en fonction de vos tâches répétitives quotidiennes ou de processus complexes pouvant quand même être automatisés. Conseils de ma part :

 - Toute tâche automatisable, que vous faites vous-même plusieurs fois par jour, doit devenir un skill.
 Écrire ses propres skills est une qualité de développeur unique et fortement conseillée. Les skills écrits à la main sont souvent plus efficaces. 
 
 - Si vous demandez à un agent de vous créer un skill, utilisez toujours writing-for-agents afin de bénéficier du meilleur format.