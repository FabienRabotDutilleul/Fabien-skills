---
name: inject_into_knowledge_base
description: Diffuser un document déjà classé de docs/refs/ vers docs/kb/ — pages atomiques reliées, provenance tracée, contradictions signalées, lint à 0 erreur.
disable-model-invocation: true
---

# inject_into_knowledge_base — du corpus reçu au savoir relié

Second temps de `create_linked_docs` (`cmd_docs/00_created_linked_docs.md`). Le document est
classé et enregistré ; il s'agit maintenant d'en **tirer du savoir** et de le relier au reste.

**Tu instruis, tu ne juges pas.** Tu rassembles les pièces, tu les confrontes, tu établis ce qui
est acquis et ce qui est contesté — et pour ce que tu ne peux pas trancher, tu nommes l'arbitre.
(Le temps 1 était un travail de greffier ; celui-ci est son opposé.)

> **Un document ne devient pas une page. Il alimente des pages.**

C'est le contre-pied de l'intuition : un document touche 3, 5, 10 objets de savoir et n'en
épuise aucun, tandis qu'un objet durable — la Note ASAP, le multi-tenant, Rodolphe — est nourri
par cinq documents. La page-par-document existe déjà, c'est `docs/refs/for_agents/<nom>/`.

## Avant de commencer

**Lire `SCHEMA.md`** à la racine du dépôt : c'est le contrat que toute page respecte, et les
étapes ci-dessous s'y réfèrent sans le recopier. Les cinq sections qui commandent ce travail :

| § | Ce qu'elle fixe |
|---|---|
| 1 | les 4 couches et la **règle de placement** (`refs/` reçu · `kb/` compris) |
| 4.2 | le frontmatter d'une page de savoir |
| 5 | les titres de **relations typées** — la structure vit dans les liens, pas dans les dossiers |
| 8 | la syntaxe des contradictions et leur registre |
| 9 | l'atomicité et le seuil de création d'une page |

Notre OKF est **adapté** : les écarts avec la spec amont sont consignés dans
`docs/refs/README.md` § Nos adaptations. En cas de doute, `SCHEMA.md` fait foi — pas la spec.

## Entrée

Un document déjà classé sous `docs/refs/` et inscrit au registre `docs/refs/index.md`. S'il est
encore dans `inbox/` ou `tmp_output/`, exécuter d'abord le temps 1
(`cmd_docs/01_extract_data_from_microsoft.md`) et s'arrêter là : la provenance ne se reconstruit
pas après coup.

Un document de **calcul** (barème, formules, tableau arithmétique) exige en plus un RAPPORT au
**contre-calcul soldé** et une relecture humaine consignée (`verified`) : une cellule décalée y
devient une règle métier fausse. Tant que l'un des deux manque, le signaler, laisser le registre
en **classé** — *en attente de validation humaine* — et s'arrêter.

## Étapes

1. **Instruire le dossier.** Lire le document **et son `RAPPORT.md`** — le rapport dit où la
   transcription est fragile (`⟦transcription visuelle⟧`, topologie inférée, `⟦illisible⟧`), et
   un fait qui n'existe que dans une zone fragile ne peut pas produire un `confidence: établi`.
   Lire aussi le `status` du frontmatter : `draft` (relecture active côté source) ⇒ tout ce qui
   en dérive naît au mieux `provisoire`, et le lint le rappellera (`W2`).
   *Terminé quand tu peux énoncer le `status` du document et la liste des zones qui interdisent
   un `établi`.*

2. **Inventorier, puis confronter à l'index.** Lister les objets de savoir dont le document
   parle, et passer chacun devant `docs/kb/index.md` :

   | Cas | Action |
   |---|---|
   | une page existe | l'**enrichir** : ajouter la source, croiser avec ce qui y est déjà écrit |
   | un slug est réservé en `code` dans l'index | **le rédiger** au chemin exact déjà annoncé |
   | rien n'existe | appliquer le **seuil** ci-dessous |

   **Seuil de création** (`SCHEMA.md` § 9) : la chose est pointée depuis ≥ 2 endroits, ou
   apparaît dans ≥ 2 sources. En dessous, c'est une mention dans une page parente — pas un
   fichier. Un `kb/` qui gonfle de pages à un seul lien entrant perd sa navigabilité.
   *Terminé quand chaque objet inventorié est rangé dans l'un des trois cas, aucun laissé de côté.*

3. **Écrire ou enrichir.** Frontmatter (`SCHEMA.md` § 4.2), dont les deux champs qui portent la
   traçabilité :
   - **`derives_from`** — les sources qui ont nourri *cette page*, en chemins depuis la racine.
     Toute source mouvante s'épingle (`POC/src/referentiel.json@5d21b7a`) : sans épinglage, la
     page peut devenir fausse sans qu'aucun fichier du dépôt n'ait bougé.
   - **`confidence`** — `établi` (≥ 2 sources concordantes, ou une source stable et `verified`) ·
     `provisoire` (source unique, ou source en `draft`) · `contesté` (les sources divergent).

   Corps : un sujet, traité en entier. Puis les **relations typées**, qui remplacent
   l'arborescence pour tout ce qui est transverse — le type de la relation est porté par le titre
   de section (`## S'appuie sur`, `## S'oppose à`, `## Acteurs`, `## Voir aussi`… liste complète
   au `SCHEMA.md` § 5). Une cible qu'on veut pointer mais qui n'existe pas encore s'écrit en
   `` `code` `` : ça réserve le chemin sans casser le lint. `## Sources` ferme la page et dit
   **ce que chaque source apporte** — c'est le pendant lisible de `derives_from`, les deux
   concordent.
   *Terminé quand chaque lien typé posé a son retour depuis la page cible* (le lint signale les
   orphelines, pas les liens à sens unique — cette réciprocité est à ta charge).

4. **Reverser ce qui n'est pas du savoir durable.** Tout ce qu'on lit n'a pas vocation à devenir
   une page :

   | Ce qu'on vient de lire | Où ça va |
   |---|---|
   | un objet durable (règle, concept, objet métier) | `docs/kb/concepts/` |
   | une chose nommable (personne, société, système) | `docs/kb/entities/` |
   | un terme de vocabulaire | `CONTEXT.md` en une ligne ; au-delà de trois lignes, une page `docs/kb/` pointée depuis là |
   | une décision prise | `map.md` § Décisions, ou un ADR si elle est structurante |
   | une question que **personne** ne sait trancher | `map.md` § Fog |
   | deux sources qui se contredisent | un **bloc Contradiction** (étape 5) — pas le Fog |
   | un fait daté, ponctuel, non durable | `map.md` § Notes |
   | une pièce manquante à réclamer | `docs/refs/index.md` § Manque / à réclamer |

   *Terminé quand plus rien du document n'attend d'être rangé : chaque élément a sa ligne, ou est
   écarté avec son motif.*

5. **Signaler les contradictions.** C'est la question la plus rentable de la procédure et la
   raison d'être du dispositif : ce que dit le document contredit-il ce qui est déjà écrit ?
   Le bloc normalisé va **sur les deux pages concernées** :

   ```markdown
   > **Contradiction — Comptage du référentiel.**
   > Le deck annonce « 73 questions · 272 réponses » ([deck](...)) ·
   > le référentiel courant du POC donne 74 / 287 (`POC/src/referentiel.json` @`5d21b7a`).
   > **Arbitre :** Rémi — **ouverte depuis** 2026-07-31.
   ```

   Le bloc est réservé aux sources qui **coexistent** et divergent. Quand une version
   **succède** à une autre (V4 → V5, nouveau commit du POC), c'est une **évolution** : elle se
   narre dans la page (« la V4 prévoyait X ; la V5 prévoit Y »), sans bloc ni `contesté`
   (`SCHEMA.md` § 8).

   Puis `confidence: contesté` sur ces pages, et une entrée au registre § Contradictions ouvertes
   de `docs/kb/index.md` — **le titre du bloc s'y retrouve mot pour mot**. Ce registre est un
   livrable : c'est l'ordre du jour des arbitrages. Une contradiction se ferme par une décision
   (→ `map.md` ou ADR) ; le bloc devient `> **Tranché le …**` et reste en place, pour qu'on
   retrouve pourquoi on a choisi.
   *Terminé quand `python3 lint.py --contradictions` affiche la contradiction sous toutes les
   pages concernées, sans `W3`.*

6. **Mettre à jour les index.** L'index du répertoire (`docs/kb/concepts/index.md`…) **et**
   l'index racine `docs/kb/index.md`. Format d'entrée : le lien, puis la `description` du
   frontmatter de la cible, reprise telle quelle. L'index racine est **le produit** — c'est ce
   qu'un agent lit pour décider où aller : y regrouper par titre `##`, jamais par dossier.
   *Terminé quand `python3 lint.py` ne sort plus d'`E3`.*

7. **Clore.** `python3 lint.py` à **0 erreur**, relire le registre compilé
   (`python3 lint.py --contradictions`), puis deux écritures :
   - le registre `docs/refs/index.md` fait passer le document de **classé** à **exploité** ;
   - `docs/kb_status.md` coche la colonne **Injecte** (✅ + date `JJ/MM/AA`, ou ❌ + motif) et
     solde `Chemin à traiter` d'un `—`. Diffusion partielle : le dire en note (« partiel :
     *tel fichier* pas encore diffusé ») et **laisser le chemin du reste à traiter** dans la
     colonne, sinon la ligne ment et le travail restant devient invisible.
   *Terminé quand le lint sort 0 erreur et que les deux fichiers portent le nouvel état.*

## Règles d'instruction

- **`refs/` s'augmente, il ne se réécrit pas.** Une erreur trouvée dans un document reçu se
  signale dans `kb/` par un bloc Contradiction, à la source elle reste telle quelle.
- **Une donnée qui vit ailleurs se cite avec son chemin épinglé** plutôt que recopiée — les
  libellés de réponses sont dans `POC/src/referentiel.json` ; les dupliquer, c'est les faire
  diverger.
- **Deux versions qui divergent produisent un bloc et un arbitre nommé**, jamais un choix
  silencieux en faveur de celle qui paraît juste.
- **Le chemin fait l'identité** (`SCHEMA.md` § 2) : un slug réservé se rédige au chemin exact
  annoncé, et une page existante garde le sien.
- Ce qui n'est pas couvert par le corpus se dit — un trou se consigne au registre § Manque.

Le raisonnement derrière cette procédure et un exemple de bout en bout (Processus BECD V4) :
`cmd_docs/02_inject_into_knowledge_base.md`.
