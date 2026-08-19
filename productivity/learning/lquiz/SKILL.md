---
name: lquiz
description: Le skill quiz joué dans le navigateur via Lavish Editor — deux questions en vol, page HTML qui devient le document de révision de la session. Même corpus, même ledger, mêmes règles que quiz.
disable-model-invocation: true
argument-hint: "Corpus et/ou thème (optionnels), ex. « docs/ », « scoring », « cette conversation »"
---

Variante de [quiz](../quiz/SKILL.md) : **tout** ce que quiz dit — corpus et workspace, sync, sélection, conception des questions, règlement, débrief — s'applique tel quel et se lit là-bas ; ce fichier ne décrit que ce qui change. Lire `../quiz/SKILL.md` et `../quiz/LEDGER-FORMAT.md` d'abord : ils sont la source, `lquiz` n'en redit rien.

Ce qui change : le **support** et le **rythme**. La session se joue dans une page HTML ouverte par `lavish-axi`, l'utilisateur répond dans la page, l'agent corrige et régénère ; et les questions vont par **volée de deux** — deux items en vol en permanence, la sonde reste individuelle. À la fin, la page corrigée est le document de révision de la session.

## Le montage

- `quiz/sessions/sNN.json` — l'état de la session, `NN` = numéro de session du ledger après incrément. Format : [STATE-FORMAT.md](STATE-FORMAT.md). Seul l'agent l'écrit.
- `quiz/sessions/sNN.html` — la page, **toujours** produite par `python3 <dossier de ce skill>/render.py quiz/sessions/sNN.json`, jamais écrite à la main : le rendu est la propriété du skill, le contenu celle de l'état.
- Aller-retour : `lavish-axi quiz/sessions/sNN.html` ouvre la page ; `lavish-axi poll quiz/sessions/sNN.html --agent-reply "…"` affiche la correction dans le panneau Conversation **et** attend les réponses suivantes. Chaque envoi de l'utilisateur revient comme un prompt `tag: lquiz` portant `data.item` (l'id, suffixé `-sonde` pour un complément), `data.answer` et, pour un QCM, `data.indices`.

Le poll bloque jusqu'à la réponse : c'est normal. Si le harnais le bascule en arrière-plan, attendre sa notification ; s'il est tué, le relancer — rien ne se perd.

## La session

1. **Sync et sélection** — exactement quiz, étapes 1 et 2. Puis écrire `quiz/sessions/sNN.json` : en-tête, `volley: 2`, et un item par fait sélectionné, **dans l'ordre de passage** — l'entrelacement des sections se décide ici, une fois pour toutes. Chaque item porte déjà son énoncé, son format, ses `expected` (fixés avant de poser, comme l'exige quiz) et, pour un QCM, ses options et `correct`. Fini quand `render.py` produit la page sans erreur et qu'elle ne montre que les deux premiers items.
2. **Ouverture** — `lavish-axi quiz/sessions/sNN.html`, puis dire à l'utilisateur en une ligne que le quiz est dans le navigateur, et lancer le poll. Fini quand le poll tourne.
3. **Volée** — à chaque retour du poll, pour **chaque** prompt reçu (un, ou deux si l'utilisateur a répondu aux deux avant d'envoyer) : consigner la réponse dans l'item, puis trancher selon quiz — verdict + `move` + `correction` citant la source, ou **sonder** si la réponse ouverte est limite (`probe.q` posée, `probe.answer` nul : la carte sonde remplace la question, l'item reste en vol). Un complément `-sonde` se tranche toujours, jamais de seconde relance. Régler la ligne du ledger de chaque item tranché **tout de suite** — promotion, rétrogradation, `due`, historique — pour qu'une session interrompue ne perde rien. Régénérer la page (`render.py`), puis relancer le poll avec `--agent-reply` : une ligne par item traité (verdict et mouvement de boîte, la justification détaillée reste dans la carte). Fini quand chaque prompt reçu a produit soit une carte corrigée et une ligne de ledger à jour, soit une carte sonde — aucune réponse reçue sans suite.
4. **Débrief** — quand le dernier item est tranché (ou sur `Send & End`) : écrire `debrief` dans l'état selon quiz étape 5, incrémenter le compteur de session du ledger, régénérer la page, `lavish-axi end quiz/sessions/sNN.html`, et donner le score en une ligne dans la conversation. Fini quand la page porte la carte Débrief, que l'en-tête du ledger porte le nouveau numéro de session, et que la session Lavish est fermée.

## Ce qui ne change pas, dit une fois

La sélection reste secrète : la page ne révèle un item qu'à son entrée en vol, `render.py` s'en charge — ne jamais annoncer la suite dans `--agent-reply`. La correction dans la page est la correction complète (verdict, attendus, justification sourcée, vocabulaire) ; le panneau Conversation n'en porte que le résumé. Si une réponse révèle un fait faux ou manquant dans le corpus, le débrief le signale, comme dans quiz.
