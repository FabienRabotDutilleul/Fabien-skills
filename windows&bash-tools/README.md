# windows&bash-tools

Les outils qui franchissent la frontière **WSL → Windows**. Un agent qui tourne dans WSL n'a
pas prise sur la machine hôte ; ce dossier la lui donne.

Deux formes du même besoin, à choisir selon qui pilote :

| | Pour | Quoi |
|---|---|---|
| [`anti-sleep/`](anti-sleep/) | **l'agent** | Le skill. Claude empêche la machine de dormir tout seul, quand il en a besoin. |
| [`awake/`](awake/) | **toi** | Les scripts. Une commande `awake` en ligne de commande, indépendante de tout agent. |


### NOTE: Clairement, utiliser le script à chaque fois, pas besoin de gacher du token.
---

## `anti-sleep/` — le skill

Empêche la machine Windows de s'endormir depuis WSL, soit pour une durée fixée, soit tant
qu'un processus tourne.

Utile quand un agent enchaîne un run long — build, ingestion, boucle `/goal` — et que la mise
en veille de l'hôte le couperait en plein milieu. L'agent l'invoque de lui-même : il n'y a rien
à taper.

Contient aussi `PROBE.md` et `scripts/sleep-probe.sh`, pour mesurer *a posteriori* si des gels
de processus ont eu lieu — la façon de vérifier qu'une nuit de run n'a pas été silencieusement
interrompue.

## `awake/` — la version script

Le même mécanisme, sorti du skill et packagé en outil autonome. Deux implémentations
équivalentes :

| Dossier | Pour qui | Prérequis |
|---|---|---|
| [`awake/Powershell/`](awake/Powershell/) | tu travailles sous Windows | PowerShell 5.1 (d'origine depuis Windows 10) |
| [`awake/wsl-Bash/`](awake/wsl-Bash/) | tu travailles dans WSL | WSL avec l'interop Windows activé |

**Installation :**

```powershell
# Windows
cd Powershell
powershell -ExecutionPolicy Bypass -File .\Install-Awake.ps1
```

```bash
# WSL
cd wsl-Bash
bash install_awake.sh
```

Dans les deux cas l'installeur finit par un **vrai test** — 60 secondes de non-veille
réellement demandées à Windows et vérifiées — et refuse de se déclarer installé si Windows a
rejeté la demande.

**Usage, identique des deux côtés :**

```
awake              menu interactif (30 min, 1 h, 2 h, 4 h, 8 h, durée libre)
awake 2h           démarrage direct — aussi 90m, 1h30, ou 45 (= 45 minutes)
awake pid 12345    reste éveillé tant que ce processus tourne
awake status       état courant et temps restant
awake stop         arrêt immédiat
awake probe start|report|stop    mesure les gels de processus
```

**`awake-dist.7z`** (23 Ko) est la même chose en archive, pour la passer à quelqu'un qui ne
clonera pas le dépôt.

---

## Comment ça marche

Les trois implémentations posent la **même assertion d'alimentation Windows**
(`SetThreadExecutionState`), portée par un processus PowerShell détaché qui survit au terminal
et au verrouillage de la session. Aucune ne simule d'activité clavier ou souris — ce n'est pas
un *mouse jiggler*, c'est une demande explicite à Windows de ne pas s'endormir.

Elles partagent le même répertoire d'état (`%LOCALAPPDATA%\anti-sleep`) : **une protection
démarrée d'un côté est visible de l'autre.** Tu peux lancer `awake 4h` à la main et voir
l'agent en tenir compte, ou l'inverse.

## Notes

Ces outils supposent **WSL2 sur Windows** et n'ont aucun sens sur macOS ou Linux natif. Le
skill garde un `.macos-original/` : la version d'origine dont il est dérivé, conservée pour
mémoire, pas maintenue.
