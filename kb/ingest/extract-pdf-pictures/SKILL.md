---
name: extract-pdf-pictures
description: Convertir un PDF de photos/scans en Markdown canonique lisible par agent — chaque page rendue en image et lue en vision, l'image fait foi — vers tmp_output/.
disable-model-invocation: true
---

# extract-pdf-pictures — catalogue à la lettre d'un PDF de photos

Convertit un PDF composé principalement de photos ou de scans en Markdown canonique dans
`tmp_output/`. Contrairement aux classeurs et présentations, il n'y a souvent **pas de
source texte sans perte** : la page rendue en image **fait foi**, le Markdown est le guide
de lecture qui s'y réfère. Tu es un **greffier**, pas un interprète : ce qui se transcrit
l'est à la lettre, ce qui ne se transcrit pas est décrit et lié, chaque inférence est
déclarée au rapport.

## Entrée

Un PDF **nativement** PDF (scan, reportage photo, dossier assemblé). Si les métadonnées
(`producer`/`creator`) révèlent un export bureautique (Word, PowerPoint, Excel) et que
l'original est obtenable : demander l'original et router vers `/ingest_docx`,
`/ingest_pptx` ou `/ingest_xlsx` — l'export a perdu des couches que l'original contient.

## Étapes

Outillage : **PyMuPDF** (`pip install pymupdf` en venv jetable), script Python jetable.

1. **Inventorier** : métadonnées (`doc.metadata` — auteur, dates, producer), n pages,
   couche texte page par page (`page.get_text()` — laquelle en a ?), images embarquées
   (`page.get_images()`), annotations (`page.annots()` — commentaires, surlignages).
   Clore sur l'inventaire chiffré — la base du rapprochement final.
2. **Rendre chaque page en image** (`page.get_pixmap(dpi=200)`) →
   `media/pages/page-NNN.png`, une image par page, aucune exception ; extraire en qualité
   native (`doc.extract_image`) les photos embarquées qui méritent mieux que le rendu de
   page → `media/`.
3. **Lire chaque page** (vision, dans l'ordre) et rendre dans un Markdown unique, une
   section `## Page N` par page, chacune liant son rendu :
   - couche texte native → **verbatim** ;
   - texte lu à l'image → transcrit, marqué `⟦transcription visuelle⟧` ;
   - élément graphique (photo, plan, schéma, carte, tampon, signature) → une ligne de
     description + lien vers l'image — **l'image fait foi**, ne pas forcer la transcription ;
   - annotations PDF → inline `💬 (auteur)` sous l'élément annoté ;
   - frontmatter OKF en tête : `type`, `title`, `description`, `resource` (chemin du PDF),
     `generated: { by: "agent:claude/extract-pdf-pictures", at: <date> }`, `status` —
     `draft` s'il reste des annotations de relecture, `stable` sinon.
4. **Rapprocher**, dans `tmp_output/<doc>/RAPPORT.md` : chaque page, image embarquée et
   annotation figure dans le Markdown ou est listée écartée avec motif ; recenser les
   pages « image seule » (décrites sans transcription) et les `⟦illisible⟧`. Terminé
   quand le rapprochement tombe juste : rien d'inventorié qui ne soit rendu ou motivé.
5. **Faire valider.** Pointer les lignes du rapport exigeant un œil humain — tout ici est
   transcription visuelle, prioriser les pages denses en texte. La validation acquise se
   consigne : `verified: [{ by: "human:<nom>", at: <date> }]`.
6. **Pointer l'avancement.** Si le dépôt porte un `docs/kb_status.md`, y créer la ligne du
   document sous le mois courant et cocher la colonne **Ingeste** — ✅ et la date `JJ/MM/AA`,
   ou ❌ et le motif si l'extraction a buté. Les deux autres colonnes restent ⬜ : classement et
   diffusion sont des étapes distinctes. Faire avancer `Chemin à traiter` vers
   `tmp_output/<nom>/` — c'est l'argument de l'étape suivante.

## Règles de fidélité

- **Verbatim** quand une couche texte existe ; sinon `⟦transcription visuelle⟧` — jamais
  l'un déguisé en l'autre.
- **L'image fait foi** : toute affirmation du Markdown doit être vérifiable en un clic
  sur le rendu de page lié.
- Marquer plutôt que deviner : `⟦illisible⟧`, `⟦?⟧`, chacun repris au rapport.
