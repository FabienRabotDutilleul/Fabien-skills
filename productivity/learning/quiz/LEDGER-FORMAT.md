# Ledger — format et sémantique

`quiz/LEDGER.md` est la source de vérité unique de ce que l'utilisateur sait : une ligne par fait testable, lue pour sélectionner les questions, réécrite après correction. Les faits sont distillés du corpus ; le ledger est le seul fichier que ce skill possède.

## En-tête

    # Ledger — session : 4 — corpus : docs/ — synced : fc5b60e (2026-07-31)

- **session** — compteur, +1 par session terminée. Toute l'arithmétique de planification compte en sessions, pas en jours : les sessions sont irrégulières, une révision échoit donc à un numéro de session, jamais à une date.
- **corpus** — ce dont les faits sont distillés : un chemin relatif au workspace (`.`, `docs/`, `../mon-projet/`) ou `conversation`.
- **synced** — l'état du corpus distillé en dernier. Si le corpus est un dépôt git : le hash du commit, plus la date entre parenthèses. Sinon : la date seule. Pour `conversation` : la date de la dernière distillation. L'étape de sync le compare à l'état actuel.

## Sections

Les faits sont groupés en sections thématiques numérotées ; chaque titre de section cite le ou les fichiers du corpus qu'elle distille, pour rouvrir la bonne source au moment de composer ou de corriger. Une section **Fog** peut regrouper les inconnues assumées du corpus (questions ouvertes, décisions non prises).

## Lignes d'item

    - `09.03` [b2 appli due:6] Le cache est reconstruit depuis la base à chaque démarrage ; il ne fait pas foi. — ✘s2 ✔s4

- **id** — `SS.NN`, section + rang. Stable pour toujours : l'id est l'identité du fait, jamais renuméroté ; les faits nouveaux prennent le rang suivant en fin de section.
- **box** — boîte de Leitner `b0`…`b4` (ci-dessous).
- **tier** — le tier de la dernière question posée sur ce fait (`resti`, `appli`, `transf`) ; en `b1`, c'est donc le tier à re-tenter. Absent en `b0`.
- **due** — numéro de session à partir duquel l'item redevient éligible. Absent en `b0` et `b1` (toujours éligibles).
- **fait** — énoncé compact : assez pour composer une restitution sans rouvrir la source ; rouvrir la source pour l'application et le transfert.
- **historique** — `✔`/`✘` suffixés du numéro de session, du plus ancien au plus récent ; garder les cinq dernières marques.

## Boîtes de Leitner

| box | sens | prochaine échéance | tier des questions |
|---|---|---|---|
| `b0` | jamais testé | toujours éligible | restitution |
| `b1` | raté la dernière fois | toujours éligible | le tier raté, re-tenté |
| `b2` | réussi 1× | `due` = session + 2 | application |
| `b3` | réussi 2× d'affilée | `due` = session + 4 | transfert |
| `b4` | acquis (3× d'affilée) | `due` = session + 8 | transfert uniquement |

- **Promotion** — réponse juste sans sonde : l'item monte d'une boîte (de `b0` il saute directement en `b2` ; de `b4` il reste en `b4`), `due` recalculée. Réponse juste *après* une sonde : la boîte ne bouge pas — l'item se re-teste au même niveau avant de monter.
- **Rétrogradation** — tout échec renvoie l'item en `b1`, quelle que soit sa boîte : un acquis qui glisse revient aussitôt en rotation.
- La progression des tiers suit les boîtes : un fait qui monte est interrogé sous une forme plus exigeante que celles qu'il a déjà franchies.

## Sync — distiller le corpus

Au premier passage comme à chaque session, lister ce qui a bougé depuis `synced` :

- **Corpus git** — `git -C <corpus> log --oneline <synced>..HEAD`, puis `git -C <corpus> diff --stat <synced>..HEAD` si besoin.
- **Corpus non versionné** — les fichiers modifiés depuis la date `synced` (`find <corpus> -newermt <date>`), ou tout le corpus au premier passage.
- **Conversation** — ce qui a été dit depuis la dernière distillation.

Rouvrir les sources touchées, et reverser :

- **Fait nouveau** → nouvelle ligne `b0` en fin de la section adéquate (ou nouvelle section si le thème est neuf).
- **Fait corrigé** → réécrire l'énoncé *sur place* : même id, boîte et historique conservés — l'identité du fait survit à sa formulation.
- **Item Fog résolu** → même mécanique : l'énoncé devient le fait résolu ; si la résolution contredit ce qui avait été appris, l'item redescend en `b1`.
- **Fait disparu du corpus** (périmètre abandonné) → supprimer la ligne ; son id n'est jamais réutilisé.

Mettre à jour `synced` dans l'en-tête une fois le reversement fini.
