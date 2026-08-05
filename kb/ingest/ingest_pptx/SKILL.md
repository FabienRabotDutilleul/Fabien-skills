---
name: ingest_pptx
description: Convertir une présentation PowerPoint en Markdown canonique lisible par agent — transcription à la lettre, sans perte, vers tmp_output/.
disable-model-invocation: true
---

# ingest_pptx — transcription à la lettre d'une présentation PowerPoint

Convertit un `.pptx` en Markdown canonique dans `tmp_output/`, en rendant explicite ce que
la mise en page encode implicitement : ordre de lecture, hiérarchie des blocs, diagrammes,
contenu caché à l'impression (notes de l'orateur, diapos masquées). Tu es un **greffier**,
pas un interprète : chaque texte est repris verbatim, chaque inférence est déclarée au
rapport.

## Entrée

Exiger le `.pptx` d'origine. Un PDF ou une capture d'écran n'est pas une source acceptable
(notes, SmartArt et diapos masquées perdus) : demander le fichier et s'arrêter là.
Un `.ppt` ancien : le convertir d'abord (`libreoffice --headless --convert-to pptx`).

## Étapes

1. **Extraire sans perte**, par script Python jetable :
   - `python-pptx` : texte des formes (groupes inclus, récursivement), tables, notes de
     l'orateur, diapos masquées (`slide.show`), données des graphiques (catégories/séries).
   - XML direct pour ce que `python-pptx` ne lit pas : SmartArt (`ppt/diagrams/data*.xml`
     → `<a:t>` + topologie), connecteurs (`<p:cxnSp>`, ancres `stCxn`/`endCxn` → id des
     formes reliées, la topologie explicite).
   - Copier `ppt/media/*` vers `tmp_output/<deck>/media/`.
   - Clore sur l'inventaire par diapo : n formes, n tables, n images, n SmartArt,
     notes présentes ou non — la base du rapprochement final.
2. **Ordonner.** L'ordre des formes dans le XML est le z-order, pas l'ordre de lecture :
   ordonner par position (haut → bas, gauche → droite) et signaler au rapport toute diapo
   où cet ordre reste ambigu (colonnes, blocs superposés).
3. **Rendre en Markdown** — un fichier par présentation dans `tmp_output/<deck>/` :
   - Frontmatter OKF en tête de chaque `.md` : `type`, `title`, `description`, `resource`
     (chemin du fichier source), `generated: { by: "agent:claude/ingest_pptx", at: <date> }`,
     `status` — `draft` si la source porte des marques de relecture actives (commentaires),
     `stable` sinon.
   - Une section `## Diapo N — <titre>` par diapo, diapos masquées marquées `(masquée)`.
   - Texte verbatim, tables → tables Markdown, graphique → table de ses données.
   - SmartArt et logigrammes → bloc Mermaid portant la topologie, puis le texte des nœuds.
   - Notes de l'orateur → sous-section `Notes` de la diapo.
   - Image : lien vers `media/` ; si elle porte du texte, la lire (vision) et transcrire
     en la marquant `⟦transcription visuelle⟧` — c'est une lecture, pas un verbatim.
4. **Rapprocher**, dans `tmp_output/<deck>/RAPPORT.md` :
   - Inventaire : chaque forme, table, image et note extraite figure dans le fichier
     généré, ou est listée ici comme écartée avec son motif.
   - Incertitudes : ordre de lecture inféré, topologie déduite de la position plutôt que
     d'un connecteur explicite, texte marqué `⟦illisible⟧`, transcriptions visuelles.
   Terminé quand le rapprochement tombe juste : rien d'extrait qui ne soit rendu ou motivé.
5. **Faire valider.** Livrer les fichiers et pointer les lignes du rapport qui exigent un
   œil humain — transcriptions visuelles et topologies inférées d'abord. La validation
   acquise se consigne dans le frontmatter : `verified: [{ by: "human:<nom>", at: <date> }]`.
6. **Pointer l'avancement.** Si le dépôt porte un `docs/kb_status.md`, y créer la ligne du
   document sous le mois courant et cocher la colonne **Ingeste** — ✅ et la date `JJ/MM/AA`,
   ou ❌ et le motif si l'extraction a buté. Les deux autres colonnes restent ⬜ : classement et
   diffusion sont des étapes distinctes. Faire avancer `Chemin à traiter` vers
   `tmp_output/<nom>/` — c'est l'argument de l'étape suivante.

## Règles de fidélité

- **Verbatim** : texte repris à la lettre, fautes et abréviations comprises.
- Toute sémantique portée par un visuel (couleur, gras, position, animation) reçoit une
  traduction textuelle — le lecteur du Markdown ne verra jamais l'original.
- Marquer plutôt que deviner : `⟦illisible⟧`, `⟦tronqué⟧`, `⟦?⟧`, chacun repris au rapport.
