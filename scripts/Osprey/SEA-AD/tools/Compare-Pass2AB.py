#!/usr/bin/env python3
"""
Compare two Osprey --model-diagnostics runs (OSPREY_PASS2_QVALUE=percolator vs
transfer) and emit an HTML that highlights the FDR-calibration difference, with
both Pass 1 and Pass 2 statistics (experiment-wide + per-run scopes).

Reads each run's seaad.model-diagnostics.html embedded <script type=application/json>
blob, pulls the 4 fdpViews (Pass1/2 x experiment/run), interpolates the true
combined FDP + accepted-target count at reported q = 1%, and overlays the two
methods' Pass-2 experiment-wide combined-FDP calibration curves.

Usage:
  python Compare-Pass2AB.py <percolator_run_dir> <transfer_run_dir> <out_html>
"""
import sys, re, json, html as _html


def load(path):
    txt = open(path, encoding='utf-8').read()
    m = re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', txt, re.S)
    if not m:
        raise SystemExit(f"no embedded JSON in {path}")
    return json.loads(m.group(1))


def interp(xs, ys, x0):
    if not xs:
        return float('nan')
    if x0 <= xs[0]:
        return ys[0]
    for i in range(1, len(xs)):
        if xs[i] >= x0:
            x1, x2, y1, y2 = xs[i - 1], xs[i], ys[i - 1], ys[i]
            return y2 if x2 == x1 else y1 + (y2 - y1) * (x0 - x1) / (x2 - x1)
    return ys[-1]


def views(data):
    # Current build: top-level fdpViews = pass 1; pass 2 nested under data['pass2']['fdpViews']
    # (BuildPass2 refactor). Older flat format put both in the top-level list with a 'pass' field.
    out = {}
    for v in data.get('fdpViews', []):
        out[(v['pass'], v['scope'])] = v
    p2 = data.get('pass2') or {}
    for v in (p2.get('fdpViews') or []):
        out[(v['pass'], v['scope'])] = v
    return out


def fmt_pct(x):
    return '-' if x != x else f"{x*100:.3f}%"


def _resolve_html(arg):
    import os
    if arg.lower().endswith('.html'):
        return arg
    arg = arg.rstrip('/\\')
    for name in ('out.model-diagnostics.html', 'seaad.model-diagnostics.html', 'caldiag.model-diagnostics.html'):
        p = os.path.join(arg, name)
        if os.path.exists(p):
            return p
    raise SystemExit(f"no model-diagnostics.html found in {arg}")


def main():
    pdir, tdir, outp = sys.argv[1], sys.argv[2], sys.argv[3]
    P = load(_resolve_html(pdir))
    T = load(_resolve_html(tdir))
    pv, tv = views(P), views(T)

    Q = 0.01
    rows = []
    for (pas, scope) in [(1, 'experiment'), (2, 'experiment'), (1, 'run'), (2, 'run')]:
        pvv, tvv = pv.get((pas, scope)), tv.get((pas, scope))
        pf = interp(pvv['q'], pvv['combined'], Q) if pvv else float('nan')
        tf = interp(tvv['q'], tvv['combined'], Q) if tvv else float('nan')
        pn = interp(pvv['q'], pvv.get('nTargetAccepted') or [], Q) if pvv else float('nan')
        tn = interp(tvv['q'], tvv.get('nTargetAccepted') or [], Q) if tvv else float('nan')
        rows.append((f"Pass {pas} - {scope}", pf, tf, pn, tn))

    # Overlay curves: Pass 2 experiment-wide combined-FDP vs reported q.
    def curve(v):
        if not v:
            return []
        return list(zip(v['q'], v['combined']))
    p2 = curve(pv.get((2, 'experiment')))
    t2 = curve(tv.get((2, 'experiment')))
    p1 = curve(pv.get((1, 'experiment')))  # reference (both methods identical)

    # Console summary
    print(f"{'view':22s} {'percolator':>12s} {'transfer':>12s} {'delta(pp)':>10s}")
    for label, pf, tf, pn, tn in rows:
        d = (tf - pf) * 100 if (pf == pf and tf == tf) else float('nan')
        print(f"{label:22s} {fmt_pct(pf):>12s} {fmt_pct(tf):>12s} {d:>10.3f}")
    print("accepted@1%q (targets):")
    for label, pf, tf, pn, tn in rows:
        print(f"  {label:22s} percolator={pn:8.0f}  transfer={tn:8.0f}")

    # Build overlay SVG (log-x reported q vs true FDP, 0..5%), y=x reference.
    import math
    W, H, ml, mr, mt, mb = 720, 420, 60, 20, 20, 50
    pw, ph = W - ml - mr, H - mt - mb
    xmin, xmax = 1e-3, 0.05          # reported q
    ymin, ymax = 0.0, 0.05           # true FDP

    def sx(q):
        q = max(q, xmin)
        return ml + pw * (math.log10(q) - math.log10(xmin)) / (math.log10(xmax) - math.log10(xmin))

    def sy(f):
        f = min(max(f, ymin), ymax)
        return mt + ph * (1 - (f - ymin) / (ymax - ymin))

    def path(cur, col, dash=''):
        pts = [(sx(q), sy(f)) for q, f in cur if q >= xmin]
        if not pts:
            return ''
        d = 'M' + ' L'.join(f"{x:.1f},{y:.1f}" for x, y in pts)
        da = f' stroke-dasharray="{dash}"' if dash else ''
        return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="2"{da}/>'

    # y=x reference (reported q == true FDP -> perfect calibration)
    ref = path([(q, q) for q in [xmin, xmax]], '#888', '4 4')
    # gridlines at 1%, 2%, 5% FDP and 0.1%,1%,5% q
    grid = []
    for f in (0.01, 0.02, 0.05):
        y = sy(f); grid.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml+pw}" y2="{y:.1f}" stroke="#eee"/>')
        grid.append(f'<text x="{ml-6}" y="{y+3:.1f}" text-anchor="end" font-size="10" fill="#888">{f*100:.0f}%</text>')
    for q in (0.001, 0.01, 0.05):
        x = sx(q); grid.append(f'<line x1="{x:.1f}" y1="{mt}" x2="{x:.1f}" y2="{mt+ph}" stroke="#eee"/>')
        grid.append(f'<text x="{x:.1f}" y="{mt+ph+16}" text-anchor="middle" font-size="10" fill="#888">{q*100:g}%</text>')
    q1 = f'<line x1="{sx(0.01):.1f}" y1="{mt}" x2="{sx(0.01):.1f}" y2="{mt+ph}" stroke="#c33" stroke-width="1" stroke-dasharray="2 3"/>'
    svg = f'''<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}">
{''.join(grid)}
{q1}
{ref}
{path(p1, '#2a7')}
{path(p2, '#37c')}
{path(t2, '#e63')}
<text x="{ml+pw/2}" y="{H-6}" text-anchor="middle" font-size="12" fill="#444">reported q (log)</text>
<text x="14" y="{mt+ph/2}" transform="rotate(-90 14 {mt+ph/2})" text-anchor="middle" font-size="12" fill="#444">true combined FDP</text>
</svg>'''

    def rowhtml(label, pf, tf, pn, tn):
        d = (tf - pf) * 100 if (pf == pf and tf == tf) else float('nan')
        dcol = '#e63' if d > 0.05 else ('#2a7' if d < -0.05 else '#666')
        return (f"<tr><td>{_html.escape(label)}</td>"
                f"<td class=n>{fmt_pct(pf)}</td><td class=n>{fmt_pct(tf)}</td>"
                f"<td class=n style='color:{dcol}'>{d:+.3f}</td>"
                f"<td class=n>{pn:,.0f}</td><td class=n>{tn:,.0f}</td></tr>")

    meta = (f"library r={P.get('fdpViews',[{}])[0].get('entrapmentRatio',float('nan')):.3f}, "
            f"{P.get('fileCount','?')} files, Osprey {P.get('ospreyVersion','?')}")
    body = f"""<h1>Osprey Pass-2 q-value A/B: percolator vs transfer</h1>
<p class=sub>SEA-AD Astral DIA ({_html.escape(meta)}). True combined FDP at reported q, from each run's --model-diagnostics entrapment calibration. Arm B (transfer) hard-linked Stage 1-4 from arm A's shared cache and re-ran Stage 5 (Pass 1 FDR) onward with the same branch build, differing ONLY in OSPREY_PASS2_QVALUE.</p>
<p class=note>Pass 1 is identical between the two arms (same 1st-pass FDR); the Pass-2 row is where the q-assignment method differs (percolator retrain vs frozen-model TRIC transfer). A curve/row at or below its reported q is calibrated/conservative; above is anti-conservative.</p>
<table>
<thead><tr><th>FDR view</th><th>percolator<br>FDP@1%q</th><th>transfer<br>FDP@1%q</th><th>&Delta; (pp)</th><th>percolator<br>acc@1%q</th><th>transfer<br>acc@1%q</th></tr></thead>
<tbody>
{''.join(rowhtml(*r) for r in rows)}
</tbody></table>
<h2>Pass-2 experiment-wide calibration curve</h2>
<div class=leg><span style="color:#2a7">&#9644; Pass 1 exp-wide (both, reference)</span> &nbsp; <span style="color:#37c">&#9644; Pass 2 percolator</span> &nbsp; <span style="color:#e63">&#9644; Pass 2 transfer</span> &nbsp; <span style="color:#888">&#9644; y=x (perfect)</span></div>
{svg}
<p class=note>A curve at or below y=x is calibrated/conservative; above y=x is anti-conservative. The red dashed vertical marks reported q = 1%.</p>
"""
    doc = f"""<!doctype html><html><head><meta charset=utf-8><title>Pass-2 q A/B: percolator vs transfer</title>
<style>
body{{font:14px/1.5 system-ui,Segoe UI,Arial;margin:24px;max-width:840px;color:#222}}
h1{{font-size:20px;margin:0 0 4px}} h2{{font-size:16px;margin:24px 0 8px}}
.sub{{color:#555;margin:0 0 16px}} .note{{color:#777;font-size:12px}}
table{{border-collapse:collapse;width:100%;margin:8px 0}}
th,td{{border:1px solid #ddd;padding:6px 10px;text-align:left}}
th{{background:#f6f6f6;font-weight:600;font-size:12px}} td.n{{text-align:right;font-variant-numeric:tabular-nums}}
.leg{{font-size:12px;margin:6px 0}} svg{{border:1px solid #eee;background:#fff}}
</style></head><body>{body}</body></html>"""
    open(outp, 'w', encoding='utf-8').write(doc)
    print(f"\nWrote {outp}")


if __name__ == '__main__':
    main()
