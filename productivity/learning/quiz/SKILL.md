---
name: quiz
description: Séance de quiz adaptatif (QCM + questions ouvertes) sur un corpus — dossier de docs, base de connaissances, ou la conversation en cours. Répétition espacée par boîtes de Leitner, ledger versionné avec le corpus.
disable-model-invocation: true
argument-hint: "Corpus et/ou thème (optionnels), ex. « docs/ », « scoring », « cette conversation »"
---

L'utilisateur veut être interrogé sur ce qu'il est en train d'apprendre. C'est une demande à état : le ledger suit chaque fait testable de session en session — les échecs reviennent vite, l'acquis s'espace, et ce qui monte est interrogé sous des formes plus exigeantes. La session se déroule dans la langue de l'utilisateur, une question à la fois.

## Corpus et workspace

Le dossier courant est le workspace du quiz. Il contient (ou contiendra) `quiz/LEDGER.md` : une ligne par fait testable, avec sa boîte de Leitner et son historique ; format, sémantique des boîtes et procédure de sync : [LEDGER-FORMAT.md](LEDGER-FORMAT.md).

Le **corpus** est la source de vérité dont les faits sont distillés. Le déterminer dans cet ordre :

1. Ce que l'argument désigne (un chemin, ou « cette conversation »).
2. Sinon, le champ `corpus` de l'en-tête du ledger existant.
3. Sinon, le dossier courant lui-même (hors `quiz/`). Y entrer par ses fichiers d'entrée naturels — `README.md`, `CLAUDE.md`, un index ou une carte s'il y en a un — avant de descendre dans le détail.

Toute question doit être répondable depuis le corpus seul ; pour composer ou corriger, rouvrir le fichier source — le corpus bouge, la mémoire paramétrique non. Le skill ne possède que le ledger : il ne modifie jamais le corpus.

**Corpus = la conversation.** Il n'y a alors ni fichiers à rouvrir ni commit à comparer. La source est ce qui a été dit dans la session ; l'étape Sync distille la conversation en items `b0`. Si l'utilisateur ne veut pas de trace, ne pas créer de ledger : sélectionner et noter en mémoire, tout le reste s'applique tel quel.

## La session

1. **Sync.** Lire `quiz/LEDGER.md` (le créer s'il n'existe pas, en-tête compris) et [LEDGER-FORMAT.md](LEDGER-FORMAT.md), puis comparer l'état `synced` de l'en-tête au corpus actuel — commit HEAD si le corpus est un dépôt git, sinon les fichiers modifiés depuis la date `synced`. Si le corpus a bougé, reverser les changements dans le ledger selon la procédure de sync. Fini quand le ledger couvre le corpus courant et que l'en-tête porte le nouvel état.
2. **Sélection.** Sont éligibles : les `b1` (échecs), les `b0` (jamais testés), et les items dont la session `due` est atteinte. En choisir 8 à 12, dans cet ordre de priorité ; si un thème est demandé en argument, s'y restreindre. Entrelacer les sections — deux questions consécutives viennent de sections différentes — et, dans les `b0`, puiser d'abord dans les sections les moins couvertes par l'historique. La sélection reste secrète : l'utilisateur découvre chaque question à froid.
3. **Quiz.** Une question à la fois : la composer au tier que dicte la boîte de l'item (voir Conception des questions), attendre la réponse, corriger immédiatement — verdict, bonne réponse, une ligne de justification citant la source (fichier, ou moment de la conversation). Sur une réponse ouverte limite, **sonder** une fois : une seule relance qui force la moitié manquante, puis trancher. Fini quand chaque item sélectionné a une réponse notée.
4. **Règlement.** Appliquer promotions et rétrogradations selon [LEDGER-FORMAT.md](LEDGER-FORMAT.md), incrémenter le compteur de session, mettre à jour la ligne de chaque item interrogé. Fini quand chaque question posée en 3 a sa ligne à jour — aucune réponse non consignée.
5. **Débrief.** Le score de la session, les deux ou trois faits qui réclament le plus de travail, ce que la prochaine session martèlera. Si une réponse a révélé un fait faux ou manquant *dans le corpus*, le signaler ici — l'entretien du corpus appartient au projet qui le porte, pas à ce skill.

## Conception des questions

Trois tiers de **Bloom** — le tier d'un item est dicté par sa boîte ([LEDGER-FORMAT.md](LEDGER-FORMAT.md)) :

- **Restitution** — restituer le fait tel quel. « Quels sont les trois états possibles de X ? »
- **Application** — mobiliser le fait dans un scénario concret. « Un utilisateur fait A alors que le système est dans l'état B : que se passe-t-il ? »
- **Transfert** — combiner plusieurs faits ou raisonner sur les conséquences. « Le composant C tombe : qu'est-ce qui est perdu, qu'est-ce qui se reconstruit depuis D, et pourquoi ? »

Formats, mélangés dans la session — viser une moitié de questions ouvertes :

- **QCM** (simple ou multiple — annoncer « plusieurs réponses ») : 4 à 6 options de longueur équivalente (±20 %), de même registre et de même précision. Chaque distracteur est un fait voisin réel du corpus — les confusions que le domaine invite vraiment (deux termes proches que le corpus distingue, un état contre un statut, la règle générale contre son exception) — jamais du remplissage inventé.
- **Question ouverte** : fixer les points-clés attendus *avant* de la poser ; noter contre eux, crédit partiel admis. Si le corpus tient un glossaire ou un vocabulaire à éviter, une réponse juste sur le fond mais qui emploie le mauvais terme perd le point de vocabulaire — et on le dit.
- **Question Fog** : si le corpus assume des inconnues (section Fog du ledger), les tester aussi — la bonne réponse est « on ne sait pas encore », plus pourquoi et par qui/quoi on compte le savoir. Connaître le bord de la carte fait partie de la maîtrise.
