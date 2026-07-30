#!/usr/bin/env python3
"""Two-factor model for the mean(best-2) gain.

The established mechanism needs BOTH ingredients:
  A. removable leakage - the share of accepted FALSE hits that rest on a single run, since that
     is precisely the population mean(best-2) demotes; and
  B. backfill - the reservoir of run-level-detected but experiment-rejected signal that the freed
     FDR headroom can admit (union - accepted, aggregation-independent).

Neither alone predicts the gain across cohorts (rho +0.55 and +0.21). This tests the product,
plus each factor alone on the same cohort set for a fair comparison.
"""
import os

import mbn_surface as M
from mechanism import arms
from predictor_check import pearson, rank

found = arms()
pts = []
for (label, n) in list(found):
    if n != 1 or (label, 2) not in found:
        continue
    na, files, _ = found[(label, 1)]
    d = M.load(os.path.join(M.RUNS, na))
    exp = (d.get('crossRun') or {}).get('experiment') or {}
    eh = exp.get('entrapmentRunCountHistogram') or []
    cu = ((d.get('crossRun') or {}).get('perRun') or {}).get('cumUnion') or [0]
    if not eh or not cu[-1]:
        continue
    mx = M.metrics(os.path.join(M.RUNS, na))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
    removable = sum(eh[:1]) / sum(eh)              # A: false hits that are singletons
    backfill = (cu[-1] - mx) / cu[-1]              # B: reservoir as a fraction of the union
    pts.append((label, files, removable, backfill, removable * backfill,
                100.0 * (b2 - mx) / mx))

g = [p[5] for p in pts]
print(f'n={len(pts)} cohorts')
for idx, nm in ((2, 'A removable (ent k=1 share)'), (3, 'B backfill (reservoir/union)'),
                (4, 'A x B  (two-factor)')):
    xs = [p[idx] for p in pts]
    print(f'  {nm:<28} Pearson r={pearson(xs, g):+.2f}  Spearman rho={pearson(rank(xs), rank(g)):+.2f}')

print(f'\n{"cohort":<10} {"F":>3} {"A":>6} {"B":>6} {"AxB":>7} {"gain":>7}  {"pred":>6}')
# Least-squares line through the product, purely to show how tight the relation is.
xs = [p[4] for p in pts]
mx_, my = sum(xs) / len(xs), sum(g) / len(g)
b = (sum((x - mx_) * (y - my) for x, y in zip(xs, g))
     / sum((x - mx_) ** 2 for x in xs)) if len(set(xs)) > 1 else 0
a = my - b * mx_
for p in sorted(pts, key=lambda p: p[4]):
    pred = a + b * p[4]
    print(f'{p[0]:<10} {p[1]:>3} {p[2]:>6.3f} {p[3]:>6.3f} {p[4]:>7.4f} {p[5]:>+6.1f}% '
          f'{pred:>+6.1f}%')
resid = [abs(p[5] - (a + b * p[4])) for p in pts]
print(f'\nfit gain = {a:+.2f} + {b:.1f} * (A x B);  mean |residual| = '
      f'{sum(resid)/len(resid):.2f} points, max {max(resid):.2f}')
