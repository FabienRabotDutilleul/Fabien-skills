# awake — empêcher Windows de se mettre en veille

Deux implémentations du même outil, à choisir selon d'où vous pilotez la machine.

| Dossier | Pour qui | Prérequis |
|---|---|---|
| [`Powershell/`](Powershell/) | vous travaillez sous Windows | PowerShell 5.1 (d'origine depuis Windows 10) |
| [`wsl-Bash/`](wsl-Bash/) | vous travaillez dans WSL | WSL avec l'interop Windows activé |

Les deux posent la même assertion d'alimentation Windows (`SetThreadExecutionState`),
portée par un processus PowerShell détaché qui survit au terminal et au verrouillage de la
session. Ni l'un ni l'autre ne simule d'activité clavier ou souris.

Elles partagent le même répertoire d'état (`%LOCALAPPDATA%\anti-sleep`) : une protection
démarrée d'un côté est visible de l'autre. Voir la section « Différences avec la version
WSL » du [README PowerShell](Powershell/README.md) pour le détail.

## Démarrage rapide

**Windows :**

```powershell
cd Powershell
powershell -ExecutionPolicy Bypass -File .\Install-Awake.ps1
```

**WSL :**

```bash
cd wsl-Bash
bash install_awake.sh
```

Dans les deux cas, l'installeur finit par un vrai test — 60 secondes de non-veille
réellement demandées à Windows et vérifiées — et refuse de se déclarer installé si Windows
a rejeté la demande.

## Usage, identique des deux côtés

```
awake              menu interactif (30 min, 1 h, 2 h, 4 h, 8 h, durée libre)
awake 2h           démarrage direct — aussi 90m, 1h30, ou 45 (= 45 minutes)
awake pid 12345    reste éveillé tant que ce processus tourne
awake status       état courant et temps restant
awake stop         arrêt immédiat
awake probe start|report|stop    mesure les gels de processus
```
