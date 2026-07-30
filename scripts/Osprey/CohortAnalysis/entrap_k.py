#!/usr/bin/env python3
"""Do FALSE hits repeat across adjacent runs?

Hypothesis for why sparse cohorts gain more from mean(best-2) than contiguous ones of the same
size (spread17 +11.8% vs contiguous-17 +5.2%): neighbouring files are acquired minutes apart, so
an interference that produces a false identification tends to RECUR in the next run. That gives
false hits k>=2 support, which mean(best-2) cannot demote. Sparse sampling decorrelates the runs,
leaving false hits as isolated singletons - exactly what best-2 removes.

Prediction: at matched size, contiguous cohorts carry a LARGER share of their accepted entrapment
hits at k>=2 than sparse cohorts do.

Reads crossRun.experiment.entrapmentRunCountHistogram (accepted entrapment by run count) from the
max arm of each cohort.
"""
import os

import mbn_surface as M
from mechanism import arms

PAIRS = [('17', 'spread17'), ('20', 'spread21'), ('28', 'spread28'), ('40', 'spread41')]
found = arms()


def ent_profile(label):
    if (label, 1) not in found:
        return None
    name = found[(label, 1)][0]
    d = M.load(os.path.join(M.RUNS, name))
    exp = (d.get('crossRun') or {}).get('experiment') or {}
    eh = exp.get('entrapmentRunCountHistogram') or []
    rh = exp.get('runCountHistogram') or []
    if not eh:
        return None
    tot = sum(eh)
    k1 = eh[0]
    k2p = tot - k1
    # Same split for ALL accepted precursors, as the reference: if targets also shift, the
    # difference is cohort-wide reproducibility, not something specific to false hits.
    ttot, tk1 = sum(rh), rh[0]
    return dict(ent_tot=tot, ent_k1=100.0 * k1 / tot, ent_k2p=100.0 * k2p / tot,
                all_k1=100.0 * tk1 / ttot, ratio=(100.0 * k1 / tot) / (100.0 * tk1 / ttot))


print(f'{"cohort":<10} {"F":>3} {"entrap":>7} {"ent k=1":>8} {"ent k>=2":>9} {"all k=1":>8} '
      f'{"k1 ratio":>9} {"gain":>7}')
for label in ('17', 'spread17', '20', 'spread21', '28', 'spread28', '40', 'spread41',
              '60', 'nopool75', '82'):
    p = ent_profile(label)
    if not p or (label, 2) not in found:
        continue
    files = found[(label, 1)][1]
    mx = M.metrics(os.path.join(M.RUNS, found[(label, 1)][0]))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
    print(f'{label:<10} {files:>3} {p["ent_tot"]:>7} {p["ent_k1"]:>7.1f}% {p["ent_k2p"]:>8.1f}% '
          f'{p["all_k1"]:>7.1f}% {p["ratio"]:>9.2f} {100.0*(b2-mx)/mx:>+6.1f}%')

# The k=1 enrichment of false hits - how selectively the leakage sits in the singleton bin that
# mean(best-2) attacks - across EVERY cohort, not just the matched pairs.
from predictor_check import pearson, rank                       # noqa: E402

pts = []
for (label, n) in list(found):
    if n != 1 or (label, 2) not in found:
        continue
    p = ent_profile(label)
    if not p:
        continue
    mx = M.metrics(os.path.join(M.RUNS, found[(label, 1)][0]))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
    pts.append((label, found[(label, 1)][1], p['ratio'], p['ent_k1'], 100.0 * (b2 - mx) / mx))
if len(pts) >= 5:
    g = [p[4] for p in pts]
    print(f'\nk=1 ENRICHMENT vs gain (n={len(pts)}): '
          f'Pearson r={pearson([p[2] for p in pts], g):+.2f}  '
          f'Spearman rho={pearson(rank([p[2] for p in pts]), rank(g)):+.2f}')
    print(f'entrap k=1 share vs gain: Pearson r={pearson([p[3] for p in pts], g):+.2f}  '
          f'Spearman rho={pearson(rank([p[3] for p in pts]), rank(g)):+.2f}')
    for p in sorted(pts, key=lambda p: p[2]):
        print(f'   {p[0]:<10} F={p[1]:<3} enrich {p[2]:>6.2f}  entk1 {p[3]:>5.1f}%  gain {p[4]:>+6.1f}%')

print('\nmatched-size pairs (contiguous vs sparse):')
for a, b in PAIRS:
    pa, pb = ent_profile(a), ent_profile(b)
    if not pa or not pb:
        continue
    print(f'  {a:<9} ent k>=2 {pa["ent_k2p"]:5.1f}%   vs  {b:<9} ent k>=2 {pb["ent_k2p"]:5.1f}%'
          f'   (contiguous - sparse = {pa["ent_k2p"] - pb["ent_k2p"]:+.1f} pts)')
