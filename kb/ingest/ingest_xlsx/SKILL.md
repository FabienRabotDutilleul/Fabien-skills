---
name: ingest_xlsx
description: Convertir un classeur Excel (logigrammes, processus, tableaux) en Markdown canonique lisible par agent — transcription à la lettre, sans perte, vers tmp_output/.
disable-model-invocation: true
---

# ingest_xlsx — transcription à la lettre d'un classeur Excel

Convertit un `.xlsx` en Markdown canonique dans `tmp_output/`, en rendant explicites les
deux couches que l'Excel encode implicitement : la **topologie** (position 2D, flèches,
embranchements) et les **données** (texte des boîtes et cellules). Tu es un **greffier**,
pas un interprète : chaque texte est repris verbatim, chaque inférence est déclarée au
rapport.

## Entrée

Exiger le `.xlsx` d'origine. Un PDF ou une capture d'écran d'un Excel n'est pas une source
acceptable (export tronqué, sémantique perdue) : demander le classeur et s'arrêter là.
Un `.xls` ancien : le convertir d'abord (`libreoffice --headless --convert-to xlsx`).

## Étapes

1. **Extraire sans perte**, par script Python jetable :
   - Cellules : valeurs calculées (`openpyxl`, `data_only=True`), plages fusionnées,
     couleurs de remplissage, hyperliens.
   - Formes : `openpyxl` ne les lit pas — parser `xl/drawings/drawing*.xml` : texte des
     boîtes (`<xdr:sp>` → `<a:t>`), position, remplissage ; connecteurs (`<xdr:cxnSp>`,
     ancres `stCxn`/`endCxn` → id des formes reliées, la topologie explicite).
   - Clore sur l'inventaire : n cellules non vides, n formes, n connecteurs par onglet —
     la base du rapprochement final.
2. **Décoder la légende.** Repérer la légende du classeur (ex. rouge = « Étape clé ») et
   construire la table couleur → libellé. Sans légende, décrire la couleur telle quelle
   (`Statut : fond rouge`) et le signaler au rapport.
3. **Rendre en Markdown** — un fichier par onglet dans `tmp_output/<classeur>/` :
   - Frontmatter OKF en tête de chaque `.md` : `type`, `title`, `description`, `resource`
     (chemin du fichier source), `generated: { by: "agent:claude/ingest_xlsx", at: <date> }`,
     `status` — `draft` si la source porte des marques de relecture actives (commentaires,
     révisions), `stable` sinon.
   - Onglet processus/logigramme : un bloc Mermaid `flowchart` portant la seule topologie
     (nœuds, flèches, décisions), puis une section par étape au **gabarit fixe** : mêmes
     champs, même ordre partout, champ vide = `—`. Le gabarit se déduit des libellés
     récurrents du classeur lui-même (ex. Statut, Interaction, Objet, Intrants,
     Livrables, Temps imparti, Suite) — ne pas plaquer un gabarit externe.
   - Onglet tabulaire : tables Markdown, une par bloc de données.
   - Liens internes (`'Feuille'!A1`) → renvoi nommé vers le fichier/la section générée.
4. **Rapprocher**, dans `tmp_output/<classeur>/RAPPORT.md` :
   - Inventaire : chaque cellule et forme extraite figure dans un fichier généré, ou est
     listée ici comme écartée avec son motif.
   - **Contre-calcul**, dès que la feuille calcule : rejouer l'arithmétique depuis les
     valeurs **transcrites** (colonnes dérivées, totaux) et comparer aux valeurs calculées
     que le classeur stocke en cache (`data_only=True`). Le classeur est son propre
     oracle — l'inventaire compte, le contre-calcul vérifie : un décalage de colonnes
     conserve les comptes, pas l'arithmétique. Chaque écart se range : bug d'extraction
     (corriger le script, ré-extraire, rejouer) ou erreur de la source (consigner au
     rapport, transcrire telle quelle). Un écart inexpliqué se tranche contre le rendu
     image (`libreoffice --headless --convert-to pdf`) : l'écran fait foi.
   - Incertitudes : flèche ambiguë, boîte orpheline, texte marqué `⟦illisible⟧`.
   - Toute topologie inférée de la position plutôt que d'un connecteur explicite.
   Terminé quand le rapprochement tombe juste — rien d'extrait qui ne soit rendu ou
   motivé — **et** le contre-calcul soldé : chaque écart rangé d'un côté ou de l'autre.
5. **Faire valider.** Livrer les fichiers et pointer les lignes du rapport qui exigent un
   œil humain — la topologie inférée d'abord. La validation acquise se consigne dans le
   frontmatter : `verified: [{ by: "human:<nom>", at: <date> }]`.

6. **Pointer l'avancement.** Si le dépôt porte un `docs/kb_status.md`, y créer la ligne du
   document sous le mois courant et cocher la colonne **Ingeste** — ✅ et la date `JJ/MM/AA`,
   ou ❌ et le motif si l'extraction a buté. Les deux autres colonnes restent ⬜ : classement et
   diffusion sont des étapes distinctes. Faire avancer `Chemin à traiter` vers
   `tmp_output/<nom>/` — c'est l'argument de l'étape suivante.

## Règles de fidélité

- **Verbatim** : texte repris à la lettre, fautes et abréviations comprises.
- Toute sémantique portée par un visuel (couleur, gras, position) reçoit une traduction
  textuelle — le lecteur du Markdown ne verra jamais l'original.
- Marquer plutôt que deviner : `⟦illisible⟧`, `⟦tronqué⟧`, `⟦?⟧`, chacun repris au rapport.
