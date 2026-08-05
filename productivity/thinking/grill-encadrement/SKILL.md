---
name: grill-encadrement
description: Grilling persistant pour générer et durcir les idées d'encadrement des dirigeants Rabot ; les partis pris qui tiennent se déposent en DAR.
disable-model-invocation: true
---

# Grill — Encadrement

Un grilling — un interview impitoyable, taillé comme `grill-me` — mené sur **comment encadrer et former les dirigeants Rabot Dutilleul à l'IA**. Ce qui le distingue de `grill-me` : il est **persistant**. Chaque parti pris qui tient se dépose en **DAR** (*Décision d'Accompagnement, Record* — le pendant de l'ADR) dans `dar/`, pour ne plus jamais être re-litigé.

## L'interview

Interroge-moi sans relâche sur chaque aspect de l'approche d'encadrement, jusqu'à une compréhension partagée. Descends chaque branche de l'**arbre de cadrage** — public et niveaux de maturité, format pédagogique, valeur démontrée, preuve de succès, ancrage dans la durée, logistique, registre selon l'interlocuteur — en résolvant les dépendances entre décisions **une par une**. Pour chaque question, **propose ta réponse recommandée**.

**Une seule question à la fois**, et attends mon retour avant de continuer. Plusieurs questions d'un coup, c'est déroutant.

Ancre chaque branche dans la matière réelle de la mission : les 10 use cases, les 6 angles ouverts, la règle des **deux registres** (Rémy = architecture souveraine ; dirigeants = valeur métier seule). Si une question se tranche en relisant un DAR existant, **relis le DAR** au lieu de la poser.

## Les DAR (effet de bord, inline)

Au fil de l'interview, sans casser le rythme :

- **Un parti pris d'encadrement tient** (format, angle, mesure de succès, choix de démo, dispositif d'ancrage…) → écris un DAR.
- **Une décision déjà actée revient sur la table** → relis son DAR ; ne la rouvre que sur une raison neuve, et alors *Remplace* l'ancien.
- **Un angle est écarté avec une raison qui resservira** → DAR au statut `Écarté`, pour qu'un futur grilling ne le re-propose pas.

Ne déclenche un DAR que pour ce qui est **load-bearing** : une raison qu'un toi futur devrait connaître pour ne pas refaire le débat. Les détails éphémères restent dans la conversation.

### Écrire un DAR

Fichier `dar/NNNN-slug.md`, numéro à 4 chiffres, suite à plat. Crée `dar/` et son index `dar/README.md` à la volée s'ils manquent, et **ajoute une ligne à l'index** à chaque DAR. Format :

```markdown
# DAR-NNNN — <titre net>

- **Statut** : Proposé | Retenu | Écarté | Remplacé par DAR-XXXX
- **Date** : AAAA-MM-JJ
- **Audience** : dirigeants | Rémy | les deux | interne (méthode)
- **Use cases liés** : #1, #2… (si pertinent)

## Contexte
La question d'encadrement à trancher.

## Décision
Le parti pris retenu, en une phrase nette.

## Pourquoi
Ce qui le rend load-bearing — la raison qu'un futur grilling doit connaître pour ne pas re-litiger.

## Conséquences
Ce que ça change concrètement pour la prochaine session ou la prépa.

## Alternatives écartées
(optionnel) Ce qu'on n'a pas retenu, et pourquoi.
```
