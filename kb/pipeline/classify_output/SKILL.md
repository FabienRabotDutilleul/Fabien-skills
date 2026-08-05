---
name: classify_output
description: Classer une transcription de tmp_output/ dans docs/refs/for_agents/ et son original d'inbox/ dans docs/refs/for_human/ — arborescence miroir + enregistrement au registre index.md.
disable-model-invocation: true
---

# classify_output — classement miroir d'une transcription

Range le produit d'une ingestion (ex. `/ingest_xlsx`) selon la convention du corpus :
**même nom de dossier des deux côtés** — `docs/refs/for_agents/<nom>/` pour les agents (Markdown),
`docs/refs/for_human/<nom>/` pour les humains (original intact).

## Étapes

1. **Apparier.** Identifier le dossier `tmp_output/<nom>/` et le(s) fichier(s) original(aux)
   correspondant(s) dans `inbox/`. Si plusieurs candidats se disputent l'appariement,
   demander plutôt que choisir.
2. **Classer**, depuis la racine du dépôt :
   ```
   .claude/skills/classify_output/classify.sh <nom> "inbox/<original>"
   ```
   Le script déplace la transcription vers `docs/refs/for_agents/<nom>/`, l'original vers
   `docs/refs/for_human/<nom>/`, réécrit les références `inbox/…` des Markdown vers le
   miroir humain, supprime le `:Zone.Identifier` et efface `tmp_output/` s'il est vide.
   Terminé quand `tmp_output/<nom>/` n'existe plus et qu'`inbox/` ne contient plus l'original.
3. **Compléter le frontmatter OKF** des Markdown classés (convention :
   `docs/refs/README.md`) : l'ingesteur ne connaît que le fichier, le classement connaît
   la provenance — remplir `sources` (author, channel, received) et vérifier que les
   `resource` pointent vers le miroir `for_human/` après la réécriture du script.
4. **Enregistrer** au registre `docs/refs/index.md` (une ligne du tableau : Reçu, Source,
   Document, Classé sous, Statut) en puisant les points clés et le statut dans le
   `RAPPORT.md` de la transcription ; reporter chaque pièce manquante ou lien mort dans
   la section « Manque / à réclamer ».
5. **Pointer l'avancement** dans `docs/kb_status.md` : cocher la colonne **Classify** de la
   ligne du document (✅ + date `JJ/MM/AA`, ou ❌ + motif). Créer la ligne sous le mois courant
   si l'ingestion n'en a pas posé — c'est le cas d'un email collé ou d'un `.md` reçu, dont la
   colonne **Ingeste** vaut alors `—` (sans objet). La colonne **Injecte** reste ⬜, et
   `Chemin à traiter` avance de `tmp_output/<nom>/` vers le chemin classé sous `docs/refs/` —
   c'est l'argument que `/inject_into_knowledge_base` recevra.
6. **Passer le relais.** Le classement clôt le temps 1 (`cmd_docs/01_extract_data_from_microsoft.md`) :
   le corpus reçu est complet et tracé, et **rien n'en a encore été compris**. La diffusion vers
   `docs/kb/` est le temps 2 — `/inject_into_knowledge_base` — le signaler, sans le faire ici.
