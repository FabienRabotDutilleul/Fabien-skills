---
name: ingest_docx
description: Convertir un document Word en Markdown canonique lisible par agent — transcription à la lettre, couche invisible comprise, vers tmp_output/.
disable-model-invocation: true
---

# ingest_docx — transcription à la lettre d'un document Word

Convertit un `.docx` en Markdown canonique dans `tmp_output/`. Le texte affiché n'est que
la surface : le fichier contient aussi une **couche invisible** — révisions en attente,
commentaires, texte masqué, notes, zones de texte — qui doit sortir avec le reste. Tu es
un **greffier**, pas un interprète : chaque texte est repris verbatim, chaque inférence
est déclarée au rapport.

## Entrée

Exiger le `.docx` d'origine. Un PDF ou une capture n'est pas une source acceptable (toute
la couche invisible y est perdue) : demander le fichier et s'arrêter là.
Un `.doc` ancien : le convertir d'abord (`libreoffice --headless --convert-to docx`).

## Étapes

1. **Extraire sans perte**, par script Python jetable :
   - `python-docx` : paragraphes avec leur style, runs, hyperliens, tables, en-têtes et
     pieds de page par section.
   - XML direct pour ce que `python-docx` ne lit pas : révisions (`<w:ins>`/`<w:del>`,
     auteur et date), commentaires (`word/comments.xml` + ancres), notes de bas de page
     et de fin (`word/footnotes.xml`, `word/endnotes.xml`), zones de texte
     (`<w:txbxContent>`), texte masqué (`<w:vanish>`), numérotation réelle des listes
     (`word/numbering.xml`, `numId`/`ilvl`).
   - Copier `word/media/*` vers `tmp_output/<doc>/media/`.
   - Clore sur l'inventaire : n paragraphes, n tables, n révisions, n commentaires,
     n notes, n zones de texte, n images — la base du rapprochement final.
2. **Décoder la structure.** Styles `Heading N` → titres `#` de niveau N ; reconstruire
   les numéros de liste depuis `numbering.xml` (le XML ne les stocke pas) ; champs :
   table des matières générée → écartée avec motif, renvois croisés → renvois nommés vers
   la section générée.
3. **Rendre en Markdown** — un fichier par document dans `tmp_output/<doc>/` :
   - Frontmatter OKF en tête de chaque `.md` : `type`, `title`, `description`, `resource`
     (chemin du fichier source), `generated: { by: "agent:claude/ingest_docx", at: <date> }`,
     `status` — `draft` s'il reste des révisions en attente ou des commentaires, `stable` sinon.
   - Texte verbatim dans la hiérarchie des titres ; en-têtes/pieds une fois par section.
   - Tables → tables Markdown ; cellule fusionnée (`gridSpan`/`vMerge`) signalée en note
     de table, Markdown ne sachant pas la représenter.
   - Notes de bas de page et de fin → notes Markdown `[^n]`.
   - Révisions → `⟦ins(auteur) : …⟧` / `⟦sup(auteur) : …⟧` inline : les deux états du
     texte survivent. Commentaires → `⟦commentaire(auteur) : …⟧` après le passage ancré.
     Texte masqué → `⟦masqué : …⟧`.
   - Image : lien vers `media/` ; si elle porte du texte, la lire (vision) et transcrire
     en la marquant `⟦transcription visuelle⟧` — c'est une lecture, pas un verbatim.
4. **Rapprocher**, dans `tmp_output/<doc>/RAPPORT.md` :
   - Inventaire : chaque élément extrait figure dans le fichier généré, ou est listé ici
     comme écarté avec son motif.
   - Couche invisible : décompte des révisions par auteur, commentaires, texte masqué —
     le document n'est pas figé tant qu'il en reste.
   - Incertitudes : `⟦illisible⟧`, transcriptions visuelles, numérotation ambiguë.
   Terminé quand le rapprochement tombe juste : rien d'extrait qui ne soit rendu ou motivé.
5. **Faire valider.** Livrer les fichiers et pointer les lignes du rapport qui exigent un
   œil humain — révisions en attente et texte masqué d'abord. La validation acquise se
   consigne dans le frontmatter : `verified: [{ by: "human:<nom>", at: <date> }]`.
6. **Pointer l'avancement.** Si le dépôt porte un `docs/kb_status.md`, y créer la ligne du
   document sous le mois courant et cocher la colonne **Ingeste** — ✅ et la date `JJ/MM/AA`,
   ou ❌ et le motif si l'extraction a buté. Les deux autres colonnes restent ⬜ : classement et
   diffusion sont des étapes distinctes. Faire avancer `Chemin à traiter` vers
   `tmp_output/<nom>/` — c'est l'argument de l'étape suivante.

## Règles de fidélité

- **Verbatim** : texte repris à la lettre, fautes et abréviations comprises.
- Toute sémantique portée par un visuel (couleur, gras, surlignage) reçoit une traduction
  textuelle — le lecteur du Markdown ne verra jamais l'original.
- Marquer plutôt que deviner : `⟦illisible⟧`, `⟦tronqué⟧`, `⟦?⟧`, chacun repris au rapport.
