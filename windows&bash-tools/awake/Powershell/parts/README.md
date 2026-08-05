# parts/ — les sources de l'installeur

Ce dossier n'est **pas** à distribuer. Les deux fichiers à livrer sont
`../Install-Awake.ps1` et `../awake.ps1` ; l'installeur embarque tout le reste.

`parts/` contient les scripts d'origine et le générateur qui les empaquette.

## Pourquoi ce dossier existe

L'installeur est auto-portant : il contient, recopiés à l'intérieur sous forme de
here-strings, les cinq scripts qu'il va écrire sur disque. C'est ce qui permet de
distribuer l'outil en deux fichiers au lieu de sept. Mais on ne travaille pas dans un
fichier de 40 Ko où les scripts sont noyés — d'où la séparation :

```
parts/AntiSleep.ps1      ─┐
parts/keepawake.ps1       │
parts/SleepProbe.ps1      ├─→ Build-Installer.ps1 ─→ ../Install-Awake.ps1
parts/probe-loop.ps1      │
../awake.ps1             ─┘
        + parts/Install-Awake.template.ps1  (le gabarit, marqueur @@PAYLOADS@@)
```

C'est le même schéma que la version WSL, dont `install_awake.sh` porte en tête « Fichier
genere : les scripts sont embarques plus bas, ne pas editer a la main » — à ceci près que
ses sources vivaient ailleurs. Ici elles sont à côté.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `AntiSleep.ps1` | Le moteur. Verrou, fichier d'état, démarrage détaché, vérification, arrêt. N'écrit que des lignes `CLÉ=valeur`, lues par la façade. |
| `keepawake.ps1` | Le porteur de l'assertion. Appelle `SetThreadExecutionState`, écrit un fichier témoin `ASSERTED=1`, dort la durée demandée (ou surveille un PID), puis relâche dans un `finally`. C'est lui que `Start-Process` lance détaché. |
| `SleepProbe.ps1` | La sonde. Démarrage, rapport des trous, corrélation avec le journal `Kernel-Power`. |
| `probe-loop.ps1` | Le battement de cœur : un horodatage epoch toutes les 10 s. |
| `Install-Awake.template.ps1` | Le gabarit de l'installeur, avec le marqueur `@@PAYLOADS@@` à l'endroit où les scripts sont injectés. |
| `Build-Installer.ps1` | Le générateur. En PowerShell lui aussi : rien dans cette distribution ne doit exiger bash. |

`awake.ps1` ne vit pas ici : il est à la racine du dossier `Powershell/`, parce qu'il est à
la fois une part embarquée **et** un fichier livré. Posé à côté de l'installeur, il prend
la priorité sur la copie embarquée — c'est ce qui permet de livrer un correctif de la
façade sans régénérer l'installeur.

## Modifier quelque chose

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-Installer.ps1
```

Le générateur relit le gabarit, injecte les cinq scripts sous forme de here-strings, et
réécrit `../Install-Awake.ps1`. **Ne jamais éditer `Install-Awake.ps1` à la main** : la
prochaine génération écrasera la modification.

## Les deux pièges que le générateur connaît

**Un `'@` en début de ligne** dans un script embarqué refermerait le here-string qui le
porte et couperait l'installeur en deux. `Build-Installer.ps1` refuse de générer dans ce
cas plutôt que de produire un fichier cassé. C'est aussi pourquoi `keepawake.ps1` déclare
sa signature P/Invoke dans une chaîne simple sur une ligne, au lieu du here-string `@'…'@`
habituel — et pourquoi le générateur assemble lui-même ses délimiteurs à l'exécution
(`'@' + "'"`), sans quoi PowerShell prendrait le `@'` de son propre code pour une vraie
ouverture de here-string.

**L'encodage.** Tous les `.ps1` de la distribution, sources comprises, sont en UTF-8 **avec
BOM** et en CRLF. Sans BOM, PowerShell 5.1 lit un `.ps1` UTF-8 avec la page de code ANSI :
les caractères de cadre du menu (`┌ ─ └ ● ○ ✓ ✗`) sont massacrés, et un `✓` dans une chaîne
suffit à casser la syntaxe du fichier. `Build-Installer.ps1` applique ce traitement aux
deux fichiers livrés ; les sources ont été normalisées une fois pour toutes.

Une exception assumée : `Build-Installer.ps1` est le seul fichier écrit en **ASCII pur**.
C'est lui qui applique le traitement d'encodage, donc le seul qui ne puisse pas compter
dessus — il doit rester lisible quelle que soit la page de code active.

## Vérifier une modification

Le parser PowerShell, sans exécuter le script :

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('C:\chemin\AntiSleep.ps1', [ref]$null, [ref]$errors)
$errors
```

Depuis WSL, copiez d'abord les fichiers sous un chemin Windows : le parser ne sait pas lire
un chemin UNC `\\wsl.localhost\…`.

Pour un test fonctionnel, appelez le moteur directement — il n'a besoin d'aucune
installation, seulement de `keepawake.ps1` à côté de lui :

```powershell
.\AntiSleep.ps1 status
.\AntiSleep.ps1 start 60
.\AntiSleep.ps1 verify     # doit afficher ASSERTIONS=active
.\AntiSleep.ps1 stop
```

Attention : l'état vit dans `%LOCALAPPDATA%\anti-sleep`, partagé avec la version WSL et
avec une éventuelle installation réelle. Vérifiez `status` avant de tester, pour ne pas
interrompre une protection en cours.
