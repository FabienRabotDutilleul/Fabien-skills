# Fabien-skills

Ma collection de skills pour Claude Code : 50 skills rangés par usage plutôt que par ordre
d'arrivée. Chaque dossier principal porte son propre README qui explique brièvement ce que fait
chacun de ses skills.

## Les six familles

| Dossier | Ce qu'on y trouve | Nb |
|---|---|---|
| [`engineering/`](engineering/) | Concevoir, écrire, relire du code et le découper en travail | 16 |
| [`productivity/`](productivity/) | Durcir une idée, l'écrire, la dessiner, l'apprendre | 16 |
| [`kb/`](kb/) | Faire entrer du savoir dans une base lisible par agent | 10 |
| [`research/`](research/) | Déléguer le travail de lecture | 3 |
| [`agent-ops/`](agent-ops/) | Configurer et cadrer les agents eux-mêmes | 4 |
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
> Il pose une denylist unique de commandes shell catastrophiques en hook PreToolUse / pre-exec
> sur **tous** les agents de la machine, pas seulement Claude Code — la liste exacte est dans
> [`agent-ops/`](agent-ops/). Execute:
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
| 🏗️ **bosser sur du code** | `engineering/setup-matt-pocock-skills` d'abord, une fois par dépôt |
| 😴 **qu'un run long ne soit pas coupé par un veille de Windows** | `windows&bash-tools/` |

---

## Installation

```bash
npx add-fabien-skills
```

Un picker s'ouvre : tu choisis les skills, où les poser (`~/.claude/skills/` pour tous tes
projets, `<projet>/.claude/skills/` pour un seul), et si l'agent a le droit de les déclencher
tout seul. Rien à cloner, rien à installer. Il annonce aussi ce qui coûte de l'argent, ce qui
doit tourner en sandbox et ce qui demande un `uv sync`/`npm i` — **avant** d'écrire.

En non interactif :

```bash
npx add-fabien-skills -s tdd,code-review -t local
npx add-fabien-skills --list
```

Le détail des options et le fonctionnement sont dans [`cli/`](cli/).

### En symlink, pour suivre les mises à jour

Le CLI copie. Si tu préfères que les évolutions du dépôt te suivent toutes seules :

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

La veille dev et IA sort d'abord sur YouTube, et personne n'a deux heures pour une conférence.
C'est le seul problème que ces skills résolvent.

### Ceux qui se lancent en sandbox

> [!WARNING]
> **Les trois skills de [`research/`](research/) lisent du contenu web arbitraire et le
> ramènent dans le contexte de l'agent. C'est un vecteur de prompt injection.**
>
> Une page, un post ou un commentaire peut contenir des instructions déguisées que l'agent
> exécutera comme si elles venaient de toi. Ces skills se lancent **dans une sandbox** — dépôt
> jetable ou conteneur, sans credentials, sans accès au reste de ta machine — et jamais sur un
> projet qui contient des secrets.

Le détail skill par skill, lequel est le plus exposé et les réflexes à garder même en sandbox
sont dans [`research/README.md`](research/README.md).

## Attribution

Cette collection agrège du travail qui n'est pas tout de moi :

| Origine | Skills |
|---|---|
| [Matt Pocock](https://github.com/mattpocock) | l'essentiel d'`engineering/`, plus `setup-matt-pocock-skills`, `writing-for-agents`, `to-questionnaire`, `wait-what`, `wizard`, la famille `grill*`, et `ask-me` (dérivé de son `ask-matt`) |
| [Cole Medin](https://github.com/coleam00) | les trois `channel-to-kb*` |
| [bradautomates](https://github.com/bradautomates/claude-video) — MIT | `watch` |

Les skills tiers sont republiés tels quels, non modifiés. Si tu es l'auteur de l'un d'eux et
que tu préfères un lien à une copie, ouvre une issue — je bascule sans discuter.

## Contexte métier

Quelques skills portent encore du contexte spécifique à mes projets et ne s'utiliseront pas
tels quels ailleurs : `quiz`, `classify_output`,
`inject_into_knowledge_base`. Ils restent publiés parce que la mécanique est réutilisable même
si le domaine ne l'est pas.

## Continuer de ton côté :


 - Les skills sont les nouvelles fonctionnalités des applications de nos jours. Il est fortement conseillé de tester et de créer tes skills toi-même en fonction de tes tâches répétitives quotidiennes ou de processus complexes pouvant quand même être automatisés. Conseils de ma part :

 - Toute tâche automatisable, que tu fais toi-même plusieurs fois par jour, doit devenir un skill.
 Écrire ses propres skills est une qualité de développeur unique et fortement conseillée. Les skills écrits à la main sont souvent plus efficaces. 
 
 - Si tu demandes à un agent de te créer un skill, utilise toujours writing-for-agents afin de bénéficier du meilleur format.