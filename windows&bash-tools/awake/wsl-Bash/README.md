# awake — empêcher Windows de se mettre en veille, depuis WSL

Pratique pour les traitements longs : builds, imports, calculs, agents qui
tournent la nuit. La protection survit à la fermeture du terminal et au
verrouillage de la session.

> **Vous travaillez sous Windows, pas dans WSL ?** Prenez plutôt
> [`../Powershell/`](../Powershell/) : même outil, mêmes commandes, sans aucune
> dépendance à WSL. Les deux versions partagent le même état — une protection
> démarrée d'un côté est visible de l'autre.

## Installation

Copiez les deux fichiers (`awake` et `install_awake.sh`) dans un dossier, ouvrez
un terminal WSL et lancez :

```bash
bash install_awake.sh
```

L'installeur vérifie l'environnement, installe les fichiers, ajoute la commande
au PATH, puis **fait un vrai test** : il demande 60 secondes de non-veille à
Windows et vérifie que la demande a été acceptée. Si ce test échoue,
l'installation s'interrompt en le disant plutôt que de laisser croire à une
protection qui n'existe pas.

Ouvrez ensuite un nouveau terminal pour que la commande soit reconnue.

## Utilisation

```bash
awake              # menu interactif : 30 min, 1 h, 2 h, 4 h, 8 h ou durée libre
awake 2h           # démarrage direct — aussi 90m, 1h30, ou 45 (= 45 minutes)
awake pid 12345    # reste éveillé tant que ce processus WSL tourne
awake status       # état courant et temps restant
awake stop         # arrêt immédiat
```

Choisir une nouvelle durée remplace la session en cours. Quitter le menu avec
`q` laisse la protection active en arrière-plan.

## Comment ça marche

`awake` ne simule pas d'activité clavier ou souris. Il utilise l'API Windows
prévue pour ça (`SetThreadExecutionState`), celle qu'emploient VLC pendant un
film ou Teams pendant un appel : le noyau enregistre une demande explicite de
rester éveillé, et la libère dès que le processus se termine. Rien ne bouge à
l'écran, le verrouillage automatique de la session n'est pas contourné, et
l'outil n'a rien du « mouse jiggler » que les politiques de sécurité
interdisent.

La demande est portée par un processus PowerShell caché, lancé détaché côté
Windows. C'est ce qui lui permet de survivre au terminal qui l'a lancé, au
verrouillage, et même à `wsl --shutdown`.

## Si des traitements s'arrêtent quand même

Sur les machines en **Modern Standby** (l'installeur vous le signale), Windows
peut geler les applications lorsque l'écran s'éteint. Pour savoir si c'est ce
qui vous arrive, une sonde enregistre un battement toutes les 10 secondes des
deux côtés, WSL et Windows :

```bash
awake probe start     # puis verrouiller et laisser la machine 20 à 30 min
awake probe report    # un trou dans le journal = un gel avéré
awake probe stop
```

## Désinstallation

```bash
bash install_awake.sh --uninstall
```

## Prérequis

WSL avec l'interop Windows activé, c'est tout. Aucun droit administrateur,
aucune installation côté Windows, aucune dépendance à télécharger.
