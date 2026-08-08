# engineering

Les skills qui touchent au code : le concevoir, l'écrire, le relire, le découper en travail.

| Skill | Ce qu'il fait |
|---|---|
| `code-review` | Relit les changements depuis un point fixe (commit, branche, merge-base) sur deux axes en parallèle — **Standards** (le code respecte-t-il les conventions documentées du dépôt ?) et **Spec** (fait-il ce que l'issue demandait ?) — et rend les deux rapports côte à côte. |
| `codebase-design` | Le vocabulaire partagé pour concevoir des *deep modules* : où placer une couture, comment approfondir une interface, comment rendre le code testable et navigable par un agent. |
| `diagnosing-bugs` | Boucle de diagnostic pour les bugs durs et les régressions de performance. Se déclenche sur « diagnose », « debug this », ou tout signalement de casse. |
| `domain-modeling` | Construit et affûte le modèle de domaine d'un projet : langage ubiquitaire, glossaire, et décisions figées en ADR numérotés. |
| `git-worktree` | Faire tourner plusieurs agents en parallèle sur un même dépôt sans collision. Couvre la création des worktrees, leur mise à niveau (`.env`, dépendances, bases, ports), le merge et le nettoyage. |
| `impeccable` | Concevoir, auditer et polir une interface : hiérarchie visuelle, charge cognitive, accessibilité, typographie, couleur, motion, états d'erreur, design tokens. Frontend uniquement. |
| `implement` | Implémente un morceau de travail à partir d'une spec ou d'un jeu de tickets. |
| `improve-codebase-architecture` | Scanne une base de code à la recherche d'opportunités d'approfondissement, les présente en rapport HTML, puis grille celle que tu choisis. |
| `prototype` | Monte un prototype jetable pour trancher une question de design — un modèle d'état tient-il debout, à quoi doit ressembler cet écran. |
| `setup-matt-pocock-skills` | **Le prérequis.** Configure un dépôt pour accueillir les autres : tracker d'issues, vocabulaire de labels de triage, layout des docs de domaine. Une fois par dépôt, avant le premier usage de `triage`, `to-tickets`, `to-spec`, `wayfinder` et `code-review` — les cinq qui le citent nommément. |
| `qa` | Session QA conversationnelle : tu signales les bugs à l'oral, l'agent explore la base en fond pour le contexte et dépose les issues GitHub. |
| `tdd` | Red-green-refactor. Pour construire une feature ou corriger un bug en partant du test. |
| `to-spec` | Transforme la conversation en cours en spec publiée sur le tracker. Pas d'interview, juste la synthèse de ce qui a déjà été dit. |
| `to-tickets` | Découpe un plan ou une conversation en tickets *tracer-bullet*, chacun déclarant ses dépendances bloquantes. |
| `triage` | Fait passer issues et PR externes dans une machine à états : catégoriser, vérifier, griller si besoin, puis rédiger un brief exploitable par un agent. |
| `wayfinder` | Cartographie un chantier trop gros pour une seule session d'agent, sous forme de tickets de décision résolus un à un jusqu'à ce que la route soit claire. |

## Attribution

`code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `implement`,
`prototype`, `qa`, `tdd`, `to-spec`, `to-tickets`, `triage`, `wayfinder`,
`improve-codebase-architecture` et `setup-matt-pocock-skills` viennent du set de skills de
**Matt Pocock**.
