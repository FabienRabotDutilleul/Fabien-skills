# productivity

Les skills qui travaillent sur la pensée plutôt que sur le code : durcir une idée, la mettre
par écrit, la dessiner, l'apprendre.

## `thinking/` — durcir une idée

| Skill | Ce qu'il fait |
|---|---|
| `grilling` | Le socle : stress-tester un plan, une décision ou une idée en interrogatoire serré. Se déclenche sur n'importe quelle formule « grill ». |
| `grill-me` | L'interview relentless, une question à la fois, pour affûter un plan ou un design. |
| `batch-grill-me` | Même chose mais toutes les questions de la frontière d'un coup, round par round. Plus rapide, moins socratique. |
| `grill-with-docs` | L'interview qui laisse une trace : les ADR et le glossaire s'écrivent au fil de l'eau. |
| `grill-encadrement` | Grilling persistant orienté encadrement de dirigeants ; les partis pris qui survivent se déposent en DAR. *Contexte métier spécifique.* |
| `decisions` | Demande à l'agent de lister tous les choix qu'il a faits pendant le travail et dont il n'est pas sûr. Manuel uniquement, via `/decisions`. |

## `writing/` — mettre par écrit

| Skill | Ce qu'il fait |
|---|---|
| `brain-to-docs` | Extrait la vision, les décisions et les préférences de ta tête vers une doc claire (README + ADR), par allers-retours en Q&R. |
| `handoff` | Compacte la conversation en cours en document de passation pour l'agent suivant. |
| `remind` | Réécrit la dernière réponse en plus court et plus simple, précédée d'un TLDR de la conversation. Manuel, via `/remind`. |

## `diagrams/` — dessiner

| Skill | Ce qu'il fait |
|---|---|
| `excalidraw-diagram` | Produit du JSON Excalidraw pour visualiser workflows, architectures et concepts. Diagrammes éditables à la main ensuite. |
| `mermaid-diagram` | Des diagrammes Mermaid soignés directement dans du Markdown. L'alternative rapide et légère en tokens à Excalidraw. |

## `learning/` — apprendre

| Skill | Ce qu'il fait |
|---|---|
| `teach` | Enseigne un concept ou une compétence en s'appuyant sur le workspace courant. |
| `quiz` | Séance de quiz adaptatif (QCM + questions ouvertes) sur un corpus de documents, pour vérifier ce qui est réellement acquis. |

## Notes

- `grilling`, `grill-me`, `batch-grill-me`, `grill-with-docs` et `prototype` forment une même
  famille : commence par `grilling` si tu ne sais pas lequel prendre.
- `excalidraw-diagram` a besoin d'un environnement Python (`references/pyproject.toml`) pour le
  rendu ; il n'est pas versionné, monte-le avec `uv sync` dans `references/`.
