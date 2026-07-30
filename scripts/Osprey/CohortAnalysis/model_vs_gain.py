#!/usr/bin/env python3
"""Does per-cohort MODEL quality explain the gain swings? At constant content span the density
series bounces (+11.8 / +1.8 / +7.4 / +4.0 / +14.6), so the driver is cohort-specific rather than
run count. Each cohort trains its own Percolator model; modelComposite is that model's
target-decoy separation (Delta-mu). If a weak model means a big mean(best-N) recovery, these
should be inversely related.
"""
import os

import mbn_surface as M
from mechanism import arms
from predictor_check import pearson, rank

found = arms()
rows = []
print(f'{"cohort":<10} {"F":>3} {"dMu":>6} {"degen":>6} {"eff":>5} {"gain":>7}')
for label in sorted({k[0] for k in found}, key=lambda s: found[(s, 1)][1] if (s, 1) in found else 0):
    if (label, 1) not in found or (label, 2) not in found:
        continue
    na, files, _ = found[(label, 1)]
    nb = found[(label, 2)][0]
    d = M.load(os.path.join(M.RUNS, na))
    mx = M.metrics(os.path.join(M.RUNS, na))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, nb))['matched']
    cu = ((d.get('crossRun') or {}).get('perRun') or {}).get('cumUnion') or [0]
    dmu = d.get('modelComposite')
    gain = 100.0 * (b2 - mx) / mx
    eff = 100.0 * mx / cu[-1] if cu[-1] else 0
    rows.append((label, files, dmu, eff, gain))
    print(f'{label:<10} {files:>3} {dmu:>6.3f} {str(d.get("modelDegenerate")):>6} '
          f'{eff:>4.0f}% {gain:>+6.1f}%')

for idx, nm in ((2, 'model dMu'), (3, 'max efficiency')):
    xs = [r[idx] for r in rows]
    gs = [r[4] for r in rows]
    print(f'{nm:<15} vs gain: Pearson r={pearson(xs, gs):+.2f}  '
          f'Spearman rho={pearson(rank(xs), rank(gs)):+.2f}   (n={len(rows)})')
