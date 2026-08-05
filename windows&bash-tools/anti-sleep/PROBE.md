# Mesurer si les processus survivent vraiment

À utiliser quand la question n'est pas « la machine dort-elle ? » mais « mes
processus continuent-ils de tourner ? ». Sur une machine **Modern Standby**
(`powercfg /a` annonce « Mode faible consommation S0 »), l'extinction de
l'écran fait basculer le système en veille connectée, où le *Desktop Activity
Moderator* gèle les applications de bureau — un gel que la veille classique
n'aurait pas produit.

`scripts/sleep-probe.sh` fait battre deux horloges toutes les 10 s, une dans
WSL et une sous Windows. Un trou dans un journal est la preuve directe d'un
gel ; comparer les deux journaux distingue un gel de toute la machine d'une
simple pause de la VM WSL.

## Protocole

```bash
scripts/sleep-probe.sh reset     # repart d'un journal vierge
scripts/sleep-probe.sh start
```

Vérifier que l'anti-sleep visé est bien actif (`scripts/anti-sleep.sh status`),
puis laisser la machine seule assez longtemps pour dépasser le seuil observé —
verrouillage compris si c'est le scénario testé. Au retour :

```bash
scripts/sleep-probe.sh report
scripts/sleep-probe.sh stop
```

Les deux sondes sont lancées détachées côté Windows : elles survivent au shell
de l'agent, au verrouillage et à la fermeture du terminal.

## Lire le résultat

| WSL | Windows | Interprétation |
|---|---|---|
| aucun trou | aucun trou | rien n'a été gelé — la protection tient |
| trou | trou aux mêmes heures | tout le système a été suspendu (Modern Standby) |
| trou | aucun trou | seule la VM WSL a été mise en pause, Windows tournait |

Un trou dont la durée égale l'absence entière signale un gel unique et non des
micro-interruptions.

## Contre-épreuve

Un « aucun trou » ne prouve la valeur du skill que si le même protocole,
anti-sleep arrêté, produit un trou. Sans cette contre-épreuve, l'absence de gel
peut simplement vouloir dire que la machine n'est jamais restée assez longtemps
inactive.

## Confirmation côté Windows

Le journal système enregistre chaque entrée en veille (Kernel-Power 42) et
chaque sortie (107), lisible sans droits administrateur :

```bash
powershell.exe -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=42,107} -MaxEvents 5 | Select-Object TimeCreated,Id | Format-Table"
```
