# windows-tools

Les skills qui franchissent la frontière WSL → Windows. Un agent qui tourne dans WSL n'a pas
prise sur la machine hôte ; ces skills la lui donnent.

| Skill | Ce qu'il fait |
|---|---|
| `anti-sleep` | Empêche la machine Windows de s'endormir depuis WSL, soit pour une durée fixée, soit tant qu'un processus tourne. Utile quand un agent enchaîne un run long — build, ingestion, boucle `/goal` — et que la mise en veille de l'hôte le couperait en plein milieu. |

## Notes

Ces skills supposent **WSL2 sur Windows** et n'ont aucun sens sur macOS ou Linux natif.
Le dossier n'en contient qu'un pour l'instant ; il existe parce que la catégorie est nette,
pas parce qu'elle est pleine.
