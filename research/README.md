# research

Déléguer le travail de lecture. Trois skills, trois niveaux d'ambition — du plus sobre au plus
lourd.

| Skill | Ce qu'il fait |
|---|---|
| `research` | Le sobre. Enquête sur une question contre des sources primaires de confiance et capture les trouvailles dans un fichier Markdown du dépôt. À prendre quand tu veux juste que la lecture soit faite et rangée. |
| `storm-research` | Le lourd. Applique la méthode STORM en 4 phases : cinq lentilles d'experts (Praticien, Académique, Sceptique, Économiste, Historien) → carte des contradictions → rapport HTML synthétisé → peer review adversarial avec vérification des sources primaires. Pour les sujets où plusieurs points de vue et des faits vérifiés comptent ; disproportionné pour une simple recherche factuelle. |
| `last30days` | Le contemporain. Cherche ce que les gens *disent réellement* d'un sujet sur les 30 derniers jours : posts et engagement depuis Reddit, X, YouTube, TikTok, Hacker News, Polymarket, GitHub et le web. Embarque un *doctor* pour diagnostiquer les sources cassées ou manquantes. |

## ⚠️ À lancer en sandbox

> [!WARNING]
> Les trois skills de ce dossier ramènent du **contenu web arbitraire** dans le contexte de
> l'agent. Une page, un post ou un commentaire peut contenir des instructions déguisées que
> l'agent exécutera comme si elles venaient de toi — c'est du **prompt injection**.

Règle : ces skills tournent dans un **dépôt jetable ou un conteneur**, sans credentials
(`.env`, tokens, clés SSH) et sans accès au reste de la machine. Jamais sur un projet client,
jamais sur un dépôt qui contient des secrets.

`last30days` est le plus exposé — il moissonne Reddit, X, YouTube, TikTok, Hacker News et
GitHub, donc du texte écrit par n'importe qui. `research` est le plus sobre, mais il lit quand
même des sources qu'il n'a pas choisies.

Deux réflexes à garder même en sandbox :

- **Relire le Markdown/HTML produit avant de le rapatrier** dans un vrai dépôt.
- **Ne pas enchaîner** un skill de recherche avec un skill qui écrit du code ou pousse sur Git
  dans la même session.

## Quand prendre lequel

- Une question a une réponse → `research`.
- Une question a plusieurs réponses défendables et tu veux voir la friction → `storm-research`.
- La réponse dépend de ce qui s'est passé récemment → `last30days`.

## Notes

`last30days` et `storm-research` produisent tous deux du HTML et interrogent des sources
externes ; ils sont sensiblement plus coûteux en tokens et en temps que `research`. `last30days`
embarque ~14 Mo d'assets d'exemple dans `assets/`.
