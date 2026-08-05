---
name: quiz
description: Séance de quiz adaptatif (QCM + questions ouvertes) sur le corpus ASAP_Agent.
disable-model-invocation: true
argument-hint: "Thème à cibler (optionnel), ex. « scoring », « sécurité »"
---

L'utilisateur veut être interrogé sur le domaine ASAP. C'est une demande à état : le ledger suit chaque fait testable de session en session — les échecs reviennent vite, l'acquis s'espace, et ce qui monte est interrogé sous des formes plus exigeantes. La session se déroule en français, une question à la fois.

## Corpus et workspace

Racine de la mission : le dossier contenant `ASAP_Agent/` (`/home/fpineau/dev/app/ASAP/`).

- **Corpus** — `ASAP_Agent/`, la source de vérité vivante. Y entrer par son `CLAUDE.md`, puis `map.md` (la carte), puis `docs/refs/INDEX.md` (le registre des documents reçus). Toute question doit être répondable depuis le corpus seul ; pour composer ou corriger, rouvrir le fichier source — le corpus bouge, la mémoire paramétrique non.
- **Workspace** — `quizz/`. `LEDGER.md` y tient une ligne par fait testable, avec sa boîte de Leitner et son historique ; format, sémantique des boîtes et procédure de sync : [LEDGER-FORMAT.md](LEDGER-FORMAT.md).

## La session

1. **Sync.** Lire `quizz/LEDGER.md` et [LEDGER-FORMAT.md](LEDGER-FORMAT.md), puis comparer le commit `synced` de l'en-tête à HEAD (`git -C ASAP_Agent log --oneline <synced>..HEAD`). Si le corpus a bougé, reverser les changements dans le ledger selon la procédure de sync. Fini quand le ledger couvre le corpus à HEAD et que l'en-tête porte le nouveau hash.
2. **Sélection.** Sont éligibles : les `b1` (échecs), les `b0` (jamais testés), et les items dont la session `due` est atteinte. En choisir 8 à 12, dans cet ordre de priorité ; si un thème est demandé en argument, s'y restreindre. Entrelacer les sections — deux questions consécutives viennent de sections différentes — et, dans les `b0`, puiser d'abord dans les sections les moins couvertes par l'historique. La sélection reste secrète : l'utilisateur découvre chaque question à froid.
3. **Quiz.** Une question à la fois : la composer au tier que dicte la boîte de l'item (voir Conception des questions), attendre la réponse, corriger immédiatement — verdict, bonne réponse, une ligne de justification citant le fichier source. Sur une réponse ouverte limite, **sonder** une fois : une seule relance qui force la moitié manquante, puis trancher. Fini quand chaque item sélectionné a une réponse notée.
4. **Règlement.** Appliquer promotions et rétrogradations selon [LEDGER-FORMAT.md](LEDGER-FORMAT.md), incrémenter le compteur de session, mettre à jour la ligne de chaque item interrogé. Fini quand chaque question posée en 3 a sa ligne à jour — aucune réponse non consignée.
5. **Débrief.** Le score de la session, les deux ou trois faits qui réclament le plus de travail, ce que la prochaine session martèlera. Si une réponse a révélé un fait faux ou manquant *dans le corpus*, le signaler ici — l'entretien du corpus appartient au circuit d'`ASAP_Agent` (inbox, `/domain-modeling`), pas à ce skill.

## Conception des questions

Trois tiers de **Bloom** — le tier d'un item est dicté par sa boîte ([LEDGER-FORMAT.md](LEDGER-FORMAT.md)) :

- **Restitution** — restituer le fait tel quel. « Quels sont les trois statuts actifs chez RDC ? »
- **Application** — mobiliser le fait dans un scénario concret. « Un opérateur fige son programme et l'admin le refuse : que se passe-t-il ? »
- **Transfert** — combiner plusieurs faits ou raisonner sur les conséquences. « Le snapshot ES est corrompu : qu'est-ce qui est perdu définitivement, qu'est-ce qui se reconstruit depuis PostgreSQL, et pourquoi ? »

Formats, mélangés dans la session — viser une moitié de questions ouvertes :

- **QCM** (simple ou multiple — annoncer « plusieurs réponses ») : 4 à 6 options de longueur équivalente (±20 %), de même registre et de même précision. Chaque distracteur est un fait voisin réel du corpus — les confusions que le domaine invite vraiment (gamme/score, statut/état, Document/Justificatif, arbo/référentiel, notice/POC) — jamais du remplissage inventé.
- **Question ouverte** : fixer les points-clés attendus *avant* de la poser ; noter contre eux, crédit partiel admis. Une réponse juste sur le fond mais qui emploie le vocabulaire à éviter du glossaire (projet, note, phase, catalogue…) perd le point de vocabulaire — et on le dit.
- **Question Fog** : le corpus assume des inconnues (section Fog du ledger). Les tester aussi — la bonne réponse est « on ne sait pas encore », plus pourquoi et par qui/quoi on compte le savoir. Connaître le bord de la carte fait partie de la maîtrise.
