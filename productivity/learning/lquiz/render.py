#!/usr/bin/env python3
"""lquiz — rend l'état d'une session (state.json) en une page HTML jouable dans Lavish Editor.

    python3 render.py <chemin/vers/state.json>     → écrit <même chemin>.html à côté

Règle cardinale héritée de quiz : la sélection reste secrète. La page ne montre que
les items tranchés (cartes corrigées, empilées dans l'ordre) et les items en vol
(au plus `volley`, chacun avec son formulaire) ; le reste n'est qu'un compteur.
Un item en vol dont la sonde attend son complément s'affiche en carte « sonde ».
Quand tout est tranché et que `debrief` est renseigné, la carte de débrief clôt la page.

Python 3 standard, sans dépendance. Le format de state.json : STATE-FORMAT.md.
"""
import html
import json
import pathlib
import sys

VERDICTS = {
    "juste":   ("Juste",             "ok"),
    "sonde":   ("Juste après sonde", "warn"),
    "partiel": ("Partiel",           "warn"),
    "faux":    ("Faux",              "ko"),
}
TIERS = {"resti": "restitution", "appli": "application", "transf": "transfert"}


def esc(t):
    return html.escape(str(t), quote=True)


def li(xs):
    return "".join(f"<li>{x}</li>" for x in xs)


def head(it, *extra):
    return (
        '<div class="chead">'
        f'<span class="qn{" live" if it.get("verdict") is None else ""}">{esc(it["id"])}</span>'
        f'<span class="tag">{esc(it["section"])}</span>'
        f'<span class="tag">{esc(it.get("box", ""))} · {esc(TIERS.get(it.get("tier"), it.get("tier", "")))}</span>'
        + "".join(extra) + "</div>"
    )


def options_block(it):
    """Options d'un QCM après correction : bonnes cochées, mauvaises choisies barrées."""
    if not it["format"].startswith("qcm"):
        return ""
    good = set(it.get("correct") or [])
    chosen = set(it.get("chosen") or [])
    rows = []
    for i, o in enumerate(it["options"]):
        mark = "✔" if i in good else ("✘" if i in chosen else "·")
        k = "good" if i in good else ("bad" if i in chosen else "")
        rows.append(f'<li class="opt {k}"><span class="mk">{mark}</span>{esc(o)}</li>')
    return f'<ul class="opts">{"".join(rows)}</ul>'


def done_card(it):
    label, cls = VERDICTS[it["verdict"]]
    pr = it.get("probe") or {}
    probe_html = ""
    if pr.get("answer") is not None:
        probe_html = (
            f'<div class="yours"><h5>Relance</h5><p class="pqq">{pr["q"]}</p>'
            f'<h5 class="mt">Ton complément</h5><p>{esc(pr["answer"])}</p></div>'
        )
    move = f'<span class="tag">{esc(it["move"])}</span>' if it.get("move") else ""
    correction = f'<p class="note">{it["correction"]}</p>' if it.get("correction") else ""
    return f"""
    <article class="card done {cls}" id="item-{esc(it['id'])}">
      {head(it, f'<span class="verdict {cls}">{label}</span>', move)}
      <div class="qtext">{it['q']}</div>
      {options_block(it)}
      <div class="yours"><h5>Ta réponse</h5><p>{esc(it.get('answer', ''))}</p></div>
      {probe_html}
      <div class="fix"><h5>Ce qui était attendu</h5><ul>{li(it['expected'])}</ul>{correction}</div>
    </article>"""


def form_field(it):
    if it["format"] == "ouverte":
        return ('<textarea name="rep" rows="6" required '
                'placeholder="Réponds avec tes mots. Le crédit partiel compte."></textarea>')
    multi = it["format"] == "qcm_multi"
    typ = "checkbox" if multi else "radio"
    rows = "".join(
        f'<label class="choice"><input type="{typ}" name="rep" value="{i}"> '
        f'<span>{esc(o)}</span></label>' for i, o in enumerate(it["options"]))
    hint = '<p class="multi">Plusieurs réponses attendues.</p>' if multi else ""
    return hint + f'<div class="choices">{rows}</div>'


def live_card(it):
    fmt = "QCM" if it["format"].startswith("qcm") else "question ouverte"
    return f"""
    <article class="card live" id="item-{esc(it['id'])}">
      {head(it, f'<span class="tag">{fmt}</span>')}
      <div class="qtext big">{it['q']}</div>
      <form data-lavish-question="{esc(it['id'])}" onsubmit="return submitAnswer(event, '{esc(it['id'])}', {str(it['format'].startswith('qcm')).lower()})">
        {form_field(it)}
        <button type="submit" class="send">Envoyer ma réponse</button>
        <p class="hint">La réponse part à l'agent dès que tu cliques « Send to Agent ». Tu peux répondre aux deux questions avant d'envoyer.</p>
      </form>
    </article>"""


def probe_card(it):
    pr = it["probe"]
    return f"""
    <article class="card probe" id="item-{esc(it['id'])}">
      {head(it, '<span class="verdict warn">Sonde — 1 seule relance</span>')}
      <div class="qtext">{it['q']}</div>
      <div class="yours"><h5>Ta réponse</h5><p>{esc(it.get('answer', ''))}</p></div>
      <div class="pq"><h5>Ce qui manque</h5>{pr['q']}</div>
      <form data-lavish-question="{esc(it['id'])}-sonde" onsubmit="return submitAnswer(event, '{esc(it['id'])}-sonde', false)">
        <textarea name="rep" rows="4" required placeholder="Complète — juste la moitié manquante."></textarea>
        <button type="submit" class="send">Envoyer le complément</button>
        <p class="hint">Après cette relance l'agent tranche : juste après sonde, l'item reste dans sa boîte et se re-testera au même niveau.</p>
      </form>
    </article>"""


def render(state):
    items = state["items"]
    volley = int(state.get("volley", 2))
    done = [i for i in items if i.get("verdict")]
    pending = [i for i in items if not i.get("verdict")]
    live, hidden = pending[:volley], pending[volley:]
    score = sum(1 for i in done if i["verdict"] in ("juste", "sonde"))
    pct = round(100 * len(done) / len(items)) if items else 0

    body = "".join(done_card(i) for i in done)
    for it in live:
        pr = it.get("probe")
        body += probe_card(it) if (pr and pr.get("answer") is None) else live_card(it)

    if hidden:
        n = len(hidden)
        tail = f"<p class='left'>{n} question{'s' if n > 1 else ''} encore à venir. La sélection reste secrète.</p>"
    elif live:
        tail = "<p class='left'>Dernières questions.</p>"
    else:
        tail = ""
        body += f"""
    <article class="card debrief">
      <h3>Débrief</h3>
      <p class="bigscore">{score} / {len(items)}</p>
      {state.get('debrief') or '<p class="hint">Débrief en cours de rédaction.</p>'}
    </article>"""

    eyebrow = " · ".join(x for x in [
        "lquiz",
        f"session {state['session']}" if state.get("session") is not None else "",
        f"corpus {state['corpus']}" if state.get("corpus") else "",
    ] if x)

    return f"""<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Quiz — {esc(state['title'])}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700;800&family=Roboto+Mono:wght@400;500;600;700&family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
<style>
:root{{--blue:#2563eb;--blue-dark:#1e3a8a;--blue-bg:#eaf1fe;--ink:#16203a;--muted:#5b6677;
--line:#e4e9f2;--soft:#f6f8fc;--green:#15803d;--green-bg:#e9f6ee;--green-line:#bfe3cc;
--amber:#b45309;--amber-bg:#fdf3e7;--amber-line:#f0d5ac;--red:#b91c1c;--red-bg:#fdecec;
--red-line:#f3c9c9;--slate:#475569;--slate-bg:#eef1f6;}}
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0;min-width:0}}
:where(p,h1,h2,h3,h4,li,td,th,code){{overflow-wrap:anywhere}}
body{{font-family:'Roboto',system-ui,sans-serif;color:var(--ink);background:#eef1f6;line-height:1.62;-webkit-font-smoothing:antialiased}}
.page{{max-width:860px;margin:0 auto;background:#fff;padding:52px 60px 76px;box-shadow:0 1px 40px rgba(22,32,58,.08)}}
.eyebrow{{font-family:'Roboto Mono',monospace;font-size:11.5px;font-weight:600;letter-spacing:.18em;text-transform:uppercase;color:var(--blue);margin-bottom:12px}}
h1{{font-family:'Montserrat',sans-serif;font-weight:800;font-size:31px;line-height:1.15;letter-spacing:-.02em;margin-bottom:12px}}
.lede{{font-size:15.5px;color:var(--muted);max-width:640px}}
.bar{{margin:26px 0 6px;height:8px;border-radius:5px;background:var(--slate-bg);overflow:hidden}}
.bar span{{display:block;height:100%;background:var(--blue);border-radius:5px;width:{pct}%}}
.barlab{{display:flex;justify-content:space-between;font-family:'Roboto Mono',monospace;font-size:11.5px;color:var(--muted)}}
.barlab b{{color:var(--ink)}}
.left{{font-family:'Roboto Mono',monospace;font-size:11.5px;color:var(--muted);text-align:center;margin-top:26px}}
.card{{border:1px solid var(--line);border-radius:12px;padding:24px 26px;margin-top:22px}}
.card.live{{border:2px solid var(--blue);box-shadow:0 6px 28px rgba(37,99,235,.12)}}
.card.probe{{border:2px solid var(--amber);background:var(--amber-bg);box-shadow:0 6px 28px rgba(180,83,9,.12)}}
.card.ok{{background:var(--green-bg);border-color:var(--green-line)}}
.card.warn{{background:var(--amber-bg);border-color:var(--amber-line)}}
.card.ko{{background:var(--red-bg);border-color:var(--red-line)}}
.chead{{display:flex;flex-wrap:wrap;align-items:center;gap:9px;margin-bottom:14px}}
.qn{{font-family:'Roboto Mono',monospace;font-weight:700;font-size:12px;color:#fff;background:var(--slate);padding:4px 10px;border-radius:5px}}
.qn.live{{background:var(--blue)}}
.tag{{font-family:'Roboto Mono',monospace;font-size:10.5px;font-weight:600;letter-spacing:.07em;text-transform:uppercase;color:var(--muted);background:var(--soft);border:1px solid var(--line);padding:3px 9px;border-radius:4px}}
.verdict{{font-family:'Roboto Mono',monospace;font-size:10.5px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;padding:3px 9px;border-radius:4px;color:#fff}}
.verdict.ok{{background:var(--green)}}.verdict.warn{{background:var(--amber)}}.verdict.ko{{background:var(--red)}}
.qtext{{font-size:15.5px;margin-bottom:14px}}
.qtext.big{{font-size:18px;line-height:1.5}}
.choices{{display:flex;flex-direction:column;gap:8px;margin:18px 0}}
.choice{{display:flex;gap:12px;align-items:flex-start;border:1px solid var(--line);border-radius:9px;padding:13px 16px;cursor:pointer;font-size:15px;background:#fff;transition:border-color .12s,background .12s}}
.choice:hover{{border-color:var(--blue);background:var(--blue-bg)}}
.choice input{{margin-top:5px;flex-shrink:0;accent-color:var(--blue);width:17px;height:17px}}
.choice:has(input:checked){{border-color:var(--blue);background:var(--blue-bg);box-shadow:inset 0 0 0 1px var(--blue)}}
.multi{{font-family:'Roboto Mono',monospace;font-size:11.5px;color:var(--amber);margin-top:10px}}
textarea{{width:100%;margin:16px 0 0;border:1px solid var(--line);border-radius:9px;padding:14px 16px;font-family:'Roboto',sans-serif;font-size:15px;line-height:1.6;color:var(--ink);resize:vertical}}
textarea:focus{{outline:none;border-color:var(--blue);box-shadow:0 0 0 3px var(--blue-bg)}}
.send{{margin-top:16px;background:var(--blue);color:#fff;border:none;border-radius:8px;padding:12px 24px;font-family:'Montserrat',sans-serif;font-weight:700;font-size:14.5px;cursor:pointer}}
.send:hover{{background:var(--blue-dark)}}
.send:disabled{{background:var(--slate);cursor:default}}
.hint{{font-size:12.5px;color:var(--muted);margin-top:10px}}
.opts{{list-style:none;margin:0 0 14px}}
.opt{{font-size:14.5px;padding:5px 0;color:var(--muted);display:flex;gap:10px}}
.opt .mk{{font-family:'Roboto Mono',monospace;font-weight:700;width:14px;flex-shrink:0}}
.opt.good{{color:var(--green);font-weight:600}}
.opt.bad{{color:var(--red);text-decoration:line-through;text-decoration-color:rgba(185,28,28,.4)}}
.yours,.fix,.pq{{border-top:1px dashed rgba(22,32,58,.16);padding-top:13px;margin-top:13px}}
.pq{{font-size:16px}}.pq b{{color:var(--amber)}}
.pqq{{font-style:normal!important;font-size:13.5px;color:var(--muted)}}
h5{{font-family:'Roboto Mono',monospace;font-size:10.5px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:7px}}
h5.mt{{margin-top:10px}}
.yours p{{font-size:14.5px;font-style:italic}}
.fix ul{{list-style:none}}
.fix li{{font-size:14.5px;padding-left:17px;position:relative;margin-bottom:6px}}
.fix li::before{{content:"›";position:absolute;left:0;color:var(--blue);font-weight:700}}
.note{{font-size:14.5px;margin-top:10px;padding-top:10px;border-top:1px dotted rgba(22,32,58,.16)}}
.note code,.qtext code{{font-family:'Roboto Mono',monospace;font-size:.92em;background:rgba(22,32,58,.06);padding:1px 5px;border-radius:4px}}
.debrief{{background:var(--soft)}}
.debrief h3{{font-family:'Montserrat',sans-serif;font-size:20px;margin-bottom:10px}}
.bigscore{{font-family:'Montserrat',sans-serif;font-weight:800;font-size:44px;color:var(--blue);letter-spacing:-.02em}}
@media(max-width:760px){{.page{{padding:34px 20px 54px}}h1{{font-size:24px}}}}
@media print{{body{{background:#fff}}.page{{box-shadow:none;padding:0}}form,.left{{display:none}}}}
</style></head>
<body><div class="page">
<div class="eyebrow">{esc(eyebrow)}</div>
<h1>{esc(state['title'])}</h1>
<p class="lede">{esc(state.get('subtitle', ''))}</p>
<div class="bar"><span></span></div>
<div class="barlab"><span><b>{len(done)}</b> / {len(items)} tranchées</span><span>score <b>{score}</b> / {len(done)}</span></div>
{body}
{tail}
</div>
<script>
function submitAnswer(ev, id, isQcm) {{
  ev.preventDefault();
  const f = ev.currentTarget;
  const raw = [...new FormData(f).getAll('rep')].map(v => String(v).trim()).filter(Boolean);
  if (!raw.length) return false;
  let shown = raw;
  if (isQcm) {{
    const labels = [...f.querySelectorAll('.choice')].map(l => l.querySelector('span').textContent.trim());
    shown = raw.map(i => '[' + i + '] ' + labels[Number(i)]);
  }}
  const txt = shown.join(' | ');
  if (!window.lavish) {{ alert('Cette page se joue via lavish-axi : la réponse ne peut pas partir.'); return false; }}
  window.lavish.queuePrompt('Réponse ' + id + ' : ' + txt, {{
    tag: 'lquiz', text: id + ' → ' + txt, element: f,
    data: {{ item: id, answer: txt, indices: isQcm ? raw.map(Number) : null }}, queueKey: id
  }});
  const b = f.querySelector('.send');
  b.disabled = true; b.textContent = 'En file — clique « Send to Agent »';
  return false;
}}
</script>
</body></html>"""


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = pathlib.Path(sys.argv[1])
    state = json.loads(src.read_text(encoding="utf-8"))
    out = src.with_suffix(".html")
    out.write_text(render(state), encoding="utf-8")
    done = sum(1 for i in state["items"] if i.get("verdict"))
    live = [i["id"] for i in state["items"] if not i.get("verdict")][: int(state.get("volley", 2))]
    print(f"{out}  — {done}/{len(state['items'])} tranchées, en vol : {', '.join(live) or 'aucune'}")


if __name__ == "__main__":
    main()
