# État de session — `quiz/sessions/sNN.json`

Le fichier que [render.py](render.py) transforme en page. Un objet par session ; l'agent est le seul à l'écrire. Tout champ texte marqué *html* accepte du balisage léger (`<b>`, `<code>`, `<br>`).

    {
      "title": "Dimensionnement VRAM — L40S 48 Go",          // h1 de la page
      "subtitle": "10 items · 4 b1, 6 b0 · corpus : docs/",  // optionnel
      "session": 7,                                          // compteur du ledger, après +1
      "corpus": "docs/",                                     // tel que l'en-tête du ledger
      "volley": 2,                                           // questions en vol simultanément
      "debrief": null,                                       // html, rempli en fin de session
      "items": [ …voir ci-dessous… ]
    }

## Item

    {
      "id": "03.02",                  // l'id du ledger — ou "c07" pour un corpus conversation sans ledger
      "section": "Topographie de la VRAM",
      "box": "b2", "tier": "appli",   // boîte au moment de la question, tier posé
      "format": "ouverte",            // "ouverte" | "qcm" | "qcm_multi"
      "q": "…",                       // html — l'énoncé
      "options": ["…", "…"],          // qcm seulement, 4 à 6
      "correct": [2],                 // qcm seulement — indices des bonnes options
      "expected": ["…", "…"],         // points-clés fixés AVANT de poser (ouverte : la grille de notation)
      "answer": null,                 // texte reçu de la page ; QCM : "[2] libellé | [4] libellé"
      "chosen": [],                   // qcm : indices choisis (depuis data.indices du prompt)
      "probe": null,                  // ou { "q": "html — la moitié manquante", "answer": null }
      "verdict": null,                // "juste" | "sonde" | "partiel" | "faux"
      "move": null,                   // "b2 → b3" | "reste en b2" | "→ b1" — le mouvement de boîte réglé
      "correction": null              // html — la justification, source citée
    }

## Ce que la page affiche selon l'état de l'item

| état | rendu |
|---|---|
| `verdict` posé | carte corrigée (verdict, ta réponse, relance éventuelle, attendus, correction) |
| `verdict` nul, `probe.q` posée, `probe.answer` nul | carte **sonde** : l'énoncé, ta réponse, ce qui manque, un champ pour le complément |
| `verdict` nul, pas de sonde, parmi les `volley` premiers non tranchés | carte **live** avec formulaire |
| au-delà | invisible — compteur seulement |

Un item entre donc en vol automatiquement dès que celui qui le précède est tranché : l'ordre de `items` est l'ordre de passage, fixé à la sélection et jamais réordonné.
