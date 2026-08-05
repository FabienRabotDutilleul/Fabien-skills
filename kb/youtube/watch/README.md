# watch

> [!WARNING]
> **Skill à risque et à coût réel — ne pas installer sans lire cette page.**
>
> - **Coût API.** Quand une vidéo n'a pas de sous-titres natifs, l'audio est envoyé à
>   l'API Whisper de **Groq** ou d'**OpenAI**. Il faut donc une clé API, et chaque
>   transcription est facturée sur ton compte.
> - **Coût en tokens.** C'est de loin le skill le plus cher du dépôt : ~50-80k tokens
>   d'images pour 80 frames en 512px. `--resolution 1024` quadruple ce chiffre. Le mode
>   `token-burner` est illimité par construction.
> - **Sortie réseau.** L'audio extrait quitte ta machine. La vidéo, elle, n'en sort jamais.
> - **Secret sur disque.** La clé est stockée en clair dans `~/.config/watch/.env` (mode
>   `0600`).
> - **Code tiers exécuté localement.** `yt-dlp` et `ffmpeg` sont invoqués par des scripts
>   Python fournis. Le SKILL.md le dit lui-même : *review scripts before first use*.
>
> Skill tiers sous licence MIT — © [bradautomates](https://github.com/bradautomates/claude-video).
> Republié ici tel quel, non modifié.

## Le principe

Claude n'a pas d'entrée vidéo. Ce skill lui en fabrique une, en décomposant la vidéo en
**deux flux que l'agent sait déjà lire** : des images (frames JPEG) et du texte (transcript
horodaté).

```
source (URL ou fichier local)
   │
   ├─ yt-dlp ────────► sous-titres natifs ─┐
   │                                       ├─► transcript horodaté
   │                  (sinon) ffmpeg -vn ──┘        │
   │                  → audio mono 16 kHz           │
   │                  → API Whisper (Groq/OpenAI)   │
   │                                                │
   └─ ffmpeg ────────► frames JPEG 512px ───────────┤
                       (détection de scènes)        │
                                                    ▼
                          l'agent `Read` chaque frame + lit le transcript
                                   → répond en citant les timestamps
```

## Le déroulé concret

1. **Préflight** (`setup.py --check`, <100 ms). Vérifie `ffmpeg` / `ffprobe` / `yt-dlp` et la
   clé Whisper. Au premier run il scaffolde `~/.config/watch/.env` et demande la clé + le
   niveau de détail par défaut.
2. **`watch.py <source>`** télécharge, extrait, transcrit, puis **imprime la liste des chemins
   de frames** avec leur timestamp.
3. L'agent fait un `Read` sur chaque chemin — c'est là que les JPEG deviennent réellement des
   images dans son contexte, en parallèle dans un seul message.
4. Il croise frames et transcript pour répondre, puis `rm -rf` le dossier de travail.

## Les deux réglages qui comptent

**Le dial `--detail`** — le curseur coût / fidélité :

| Mode | Frames | Coût |
|---|---|---|
| `transcript` | aucune | quasi nul, et **skippe le téléchargement** si les sous-titres existent |
| `efficient` | keyframes seules, cap 50 | rapide |
| `balanced` *(défaut)* | scene-aware, cap 100 | ~50-80k tokens d'images |
| `token-burner` | scene-aware, illimité | 💸 |

**`--start` / `--end`** — le mode focus. Sur une vidéo de plus de 10 minutes, un scan complet
est trop clairsemé pour être utile ; cibler `2:15` → `2:45` densifie le fps (plafonné à 2 fps
en dur) et filtre le transcript sur la même fenêtre.

## Le détail malin

`--timestamps 4:32,7:10` : la sélection visuelle rate les moments où le présentateur dit
« regardez ici », parce que pointer une slide produit *peu* de changement visuel. Le workflow
prévu tient donc en deux passes — d'abord `--detail transcript` pour lire ce qui est dit, puis
l'agent repère lui-même les indices déictiques et force une frame à ces instants exacts. C'est
explicitement laissé au jugement de l'agent plutôt qu'à une regex.

## Réduire la facture

- Commence toujours par `--detail transcript`. Sur une vidéo sous-titrée, ça ne coûte ni API
  ni tokens d'images, et ça suffit souvent.
- Sur une vidéo longue, cible une section plutôt que scanner tout.
- `--no-whisper` désactive complètement le fallback API : pas de sous-titres natifs = pas de
  transcript, mais zéro euro dépensé.
- Ne relance pas le script pour une question de suivi : les frames et le transcript sont déjà
  dans le contexte de l'agent.

Référence complète des flags : voir `SKILL.md`.
