# awake — empêcher Windows de se mettre en veille (version PowerShell native)

Même outil que la version WSL, mais qui tourne directement sur Windows : aucune
distribution Linux, aucun interop, aucune dépendance à installer.

Pratique pour les traitements longs — builds, imports, calculs, agents qui tournent la
nuit. La protection survit à la fermeture du terminal et au verrouillage de la session.

## Installation

Copiez `Install-Awake.ps1` et `awake.ps1` dans un dossier, ouvrez un terminal PowerShell
et lancez :

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Awake.ps1
```

Le `-ExecutionPolicy Bypass` évite d'avoir à toucher à la politique d'exécution de la
machine. Si les fichiers viennent d'un téléchargement, Windows les marque comme bloqués —
`Unblock-File .\*.ps1` avant de lancer.

L'installeur vérifie l'environnement, écrit les fichiers dans
`%LOCALAPPDATA%\Programs\awake`, ajoute `…\awake\bin` au PATH utilisateur, puis **fait un
vrai test** : il demande 60 secondes de non-veille à Windows et vérifie que la demande a
été acceptée. Si ce test échoue, l'installation s'interrompt en le disant plutôt que de
laisser croire à une protection qui n'existe pas.

Ouvrez ensuite un nouveau terminal pour que la commande soit reconnue.

## Utilisation

```powershell
awake              # menu interactif : 30 min, 1 h, 2 h, 4 h, 8 h ou durée libre
awake 2h           # démarrage direct — aussi 90m, 1h30, ou 45 (= 45 minutes)
awake pid 12345    # reste éveillé tant que ce processus Windows tourne
awake status       # état courant et temps restant
awake stop         # arrêt immédiat
```

Choisir une nouvelle durée remplace la session en cours. Quitter le menu avec `q` laisse
la protection active en arrière-plan.

## Comment ça marche

`awake` ne simule pas d'activité clavier ou souris. Il utilise l'API Windows prévue pour
ça (`SetThreadExecutionState`), celle qu'emploient VLC pendant un film ou Teams pendant un
appel : le noyau enregistre une demande explicite de rester éveillé, et la libère dès que
le processus se termine. Rien ne bouge à l'écran, le verrouillage automatique de la
session n'est pas contourné, et l'outil n'a rien du « mouse jiggler » que les politiques
de sécurité interdisent.

La demande est portée par un processus PowerShell caché, lancé détaché par
`Start-Process`. C'est ce qui lui permet de survivre au terminal qui l'a lancé et au
verrouillage.

## Si des traitements s'arrêtent quand même

Sur les machines en **Modern Standby** (l'installeur vous le signale), Windows peut geler
les applications lorsque l'écran s'éteint. Pour savoir si c'est ce qui vous arrive, une
sonde enregistre un battement toutes les 10 secondes :

```powershell
awake probe start     # puis verrouiller et laisser la machine 20 à 30 min
awake probe report    # un trou dans le journal = un gel avéré
awake probe stop
```

Le rapport confronte les trous au journal d'événements `Kernel-Power` : un trou doublé
d'un événement de mise en veille est une vraie suspension de la machine ; un trou **sans**
événement est un gel de processus, exactement ce qu'`awake` est censé empêcher.

## Désinstallation

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Awake.ps1 -Uninstall
```

L'état résident dans `%LOCALAPPDATA%\anti-sleep` est laissé en place — il ne consomme
rien et permet de réinstaller sans perdre l'historique de la sonde.

## Prérequis

Windows avec PowerShell 5.1 (livré d'origine depuis Windows 10) ou PowerShell 7. Aucun
droit administrateur, aucune dépendance à télécharger.

## Différences avec la version WSL

| | WSL (`../wsl-Bash/`) | PowerShell (ici) |
|---|---|---|
| Prérequis | WSL + interop Windows activé | Windows seul |
| `awake pid N` | N est un PID **WSL** | N est un PID **Windows** |
| Sonde | deux battements, WSL et Windows, pour isoler une pause de la VM WSL | un battement, confronté au journal `Kernel-Power` |
| Installation | `~/.local/bin` + `~/.local/share/awake` | `%LOCALAPPDATA%\Programs\awake` + PATH utilisateur |
| Survit à `wsl --shutdown` | oui | sans objet |

Les deux versions partagent le **même répertoire d'état**
(`%LOCALAPPDATA%\anti-sleep`) et le même processus témoin. C'est voulu : l'assertion est
une propriété de la machine, pas d'un terminal. `awake status` depuis PowerShell voit donc
une protection démarrée depuis WSL, et réciproquement. Seule nuance : un `awake pid N`
lancé depuis WSL s'affichera côté PowerShell comme un PID qui n'existe pas dans le
gestionnaire des tâches — c'est un PID WSL.

## Structure du dossier

Deux fichiers suffisent à distribuer l'outil : `Install-Awake.ps1` (auto-portant, il
embarque tous les scripts) et `awake.ps1` (posé à côté, il prend la priorité sur la copie
embarquée — pratique pour livrer un correctif sans régénérer l'installeur).

`parts/` contient les sources et le générateur :

| Fichier | Rôle |
|---|---|
| `AntiSleep.ps1` | le moteur : verrou, état, démarrage détaché, vérification, arrêt |
| `keepawake.ps1` | le porteur de l'assertion, lancé détaché ; c'est lui qui appelle `SetThreadExecutionState` |
| `SleepProbe.ps1` | la sonde : démarrage, rapport, corrélation avec `Kernel-Power` |
| `probe-loop.ps1` | le battement de cœur, un horodatage toutes les 10 s |
| `Install-Awake.template.ps1` | le gabarit de l'installeur, avec le marqueur `@@PAYLOADS@@` |
| `Build-Installer.ps1` | régénère `../Install-Awake.ps1` depuis le gabarit et les parts |

Après toute modification d'une part :

```powershell
powershell -ExecutionPolicy Bypass -File .\parts\Build-Installer.ps1
```

Le générateur refuse d'embarquer un script contenant une ligne commençant par `'@`, qui
refermerait le here-string et couperait l'installeur en deux.

Tous les `.ps1`, sources comprises, sont en **UTF-8 avec BOM et fins de ligne CRLF** : sans
BOM, PowerShell 5.1 lit un `.ps1` UTF-8 avec la page de code ANSI et massacre les
caractères de cadre du menu — un seul `✓` dans une chaîne suffit alors à casser la syntaxe
du fichier.
