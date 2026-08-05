# kb

Faire entrer du savoir dans une base de connaissances lisible par agent. Trois étages : ce qui
convertit un fichier reçu, ce qui va chercher la matière ailleurs, et ce qui la range.

## `ingest/` — un fichier reçu → du Markdown canonique

Tous ces skills partagent la même doctrine : **transcription à la lettre, sans perte, vers
`tmp_output/`**. Ils ne résument pas et n'interprètent pas — ils rendent lisible.

| Skill | Ce qu'il fait |
|---|---|
| `ingest_docx` | Word → Markdown canonique, couche invisible comprise (commentaires, révisions, notes). |
| `ingest_pptx` | PowerPoint → Markdown canonique, sans perte. |
| `ingest_xlsx` | Excel → Markdown canonique. Pensé pour les logigrammes, processus et grands tableaux. |
| `extract-pdf-pictures` | PDF de scans ou de photos → Markdown. Chaque page est rendue en image puis lue en vision : **l'image fait foi**, pas la couche texte du PDF. |

## `youtube/` — aller chercher la matière dans la vidéo

| Skill | Ce qu'il fait |
|---|---|
| `channel-to-kb` | Construit une base OKF (Open Knowledge Format) à partir d'une chaîne YouTube. Gratuit, sans clé API, via `pytubefix` + `youtube_transcript_api`. |
| `channel-to-kb-ytdlp` | Même sortie, via `yt-dlp` — la variante la plus fiable. Gratuit, sans clé API. |
| `channel-to-kb-supadata` | Même sortie, via l'API managée Supadata. **Payant.** |
| `watch` | Regarde *une* vidéo (URL ou fichier local) : frames + transcript horodaté, pour répondre à des questions dessus. ⚠️ **Coûteux et à risque — lire `watch/README.md` avant de l'installer.** |

## `pipeline/` — ranger ce qui est entré

| Skill | Ce qu'il fait |
|---|---|
| `classify_output` | Classe une transcription de `tmp_output/` dans `docs/refs/for_agents/` et son original dans `docs/refs/for_human/` — arborescence miroir + enregistrement au registre. |
| `inject_into_knowledge_base` | Diffuse un document déjà classé de `docs/refs/` vers `docs/kb/` : pages atomiques reliées, provenance tracée, contradictions signalées, lint à zéro erreur. |

## Notes

Le couple `classify_output` / `inject_into_knowledge_base` matérialise une distinction
structurante : **`refs/` = ce qui a été reçu, `kb/` = ce qui a été compris**. Les deux skills
supposent cette arborescence et un frontmatter OKF dans le dépôt cible.

## Basé sur le standard de knowledge based de Google

https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf
