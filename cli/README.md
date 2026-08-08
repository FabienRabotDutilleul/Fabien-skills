# add-fabien-skills

Installe les skills de [Fabien-skills](https://github.com/FabienRabotDutilleul/Fabien-skills)
dans Claude Code, en une commande, sans cloner le dépôt.

```bash
npx add-fabien-skills
```

Un picker s'ouvre : tu choisis les skills, où les poser, si l'agent a le droit de les déclencher
tout seul. Rien d'autre à installer.

![picker](#)

## Non interactif

```bash
npx add-fabien-skills -s tdd,code-review -t local
npx add-fabien-skills -s all -t global --force
npx add-fabien-skills --list
```

| Option | |
|---|---|
| `-s, --skills <a,b,c>` | skills à installer par nom, ou `all` |
| `-t, --target <where>` | `global` → `~/.claude/skills` · `local` → `./.claude/skills` |
| `-d, --dmi <bool>` | force `disable-model-invocation` ; par défaut on garde le réglage du dépôt |
| `-f, --force` | écrase sans demander |
| `-l, --list` | liste les skills puis sort |
| `-n, --dry-run` | montre le plan, n'écrit rien |
| `--ref <ref>` | branche ou tag du dépôt |
| `--source <path>` | lit un dépôt local au lieu de GitHub |

## Comment ça marche

Le CLI ne clone jamais. Il lit [`skills.json`](../skills.json) à la racine du dépôt — une seule
requête de ~12 Ko gzippés — puis télécharge uniquement les fichiers des skills choisis.

C'est délibéré : le tarball du dépôt pèse ~16 Mo, presque entièrement les médias d'un seul skill
(`research/last30days/assets`). Cloner pour installer un skill de 7 Ko serait la façon la plus
lente de faire les choses.

L'index porte, pour chaque skill : son chemin, sa description, ses avertissements, sa liste de
fichiers avec leur taille et leur **bit exécutable** — `raw.githubusercontent.com` sert le contenu
sans les permissions, donc sans ça les 16 lanceurs embarqués de la collection arriveraient non
exécutables.

Aucune dépendance runtime. Pour un outil `npx`, chaque dépendance est du téléchargement que
l'utilisateur subit avant de voir le premier pixel.

## Développer

```bash
npm install          # `yaml`, uniquement pour générer l'index
npm test             # 13 tests, runner natif de Node
npm start            # lance le CLI sur le dépôt local
npm run index        # régénère ../skills.json
npm run index:check  # échoue si l'index est périmé
```

`npm run index` est la seule étape obligatoire après avoir ajouté, renommé ou supprimé un skill —
sinon `npx add-fabien-skills` ne le voit pas. Le générateur refuse d'écrire si un `SKILL.md` a un
frontmatter invalide, si `name:` ne correspond pas au nom du dossier, ou si deux skills partagent
un nom : ce sont exactement les cas où l'installation écraserait la mauvaise cible.
