#!/usr/bin/env python3
"""Does the gain track the RESERVOIR of detected-but-unaccepted signal?

The mechanism established from the k-slice decomposition says mean(best-N) demotes leaky
singletons and spends the resulting FDR headroom on reproducible precursors. So the gain should
scale with how much reproducible signal the max baseline has pushed below its cut.

An aggregation-INDEPENDENT measure of "signal detected somewhere" is the per-file accepted union
(crossRun.perRun.cumUnion), because per-file passing is gated on the RUN-level q, which mean(best-N)
provably does not touch (verified: per-file tables byte-identical between arms). This script
checks that invariance first, then correlates the gain against:

  reservoir      = union size - experiment-accepted count (max arm)
  reservoir_frac = reservoir / union size
  union_fdp      = purity of that union

Contrast with the frontier block, which is NOT usable as a bound: its expPeak moves with the
aggregation and is scoped differently from the fdpView (four cohorts sit above their own frontier).
"""
import os
import statistics as st

import mbn_surface as M
from predictor_check import pearson, rank


def main():
    found = {}
    for name in sorted(os.listdir(M.RUNS)):
        if not os.path.isdir(os.path.join(M.RUNS, name)):
            continue
        info = M.classify(name)
        if not info:
            continue
        label, files, n, kind = info
        vals = M.metrics(os.path.join(M.RUNS, name))
        if vals is None:
            continue
        found.setdefault((label, n), (name, files, vals))

    print('CONTROL: is cumUnion (per-file union, run-level gate) aggregation-independent?')
    bad = 0
    for (label, n), (name, files, _) in sorted(found.items()):
        if n != 1 or (label, 2) not in found:
            continue
        a = ((M.load(os.path.join(M.RUNS, name)).get('crossRun') or {}).get('perRun') or {})
        b = ((M.load(os.path.join(M.RUNS, found[(label, 2)][0])).get('crossRun') or {})
             .get('perRun') or {})
        if a.get('cumUnion') != b.get('cumUnion'):
            bad += 1
            print(f'  {label}: DIFFERS  max last={a.get("cumUnion", [0])[-1]} '
                  f'best-2 last={b.get("cumUnion", [0])[-1]}')
    print(f'  -> {"all identical" if not bad else f"{bad} cohort(s) differ"}\n')

    rows = []
    print(f'{"cohort":<10} {"F":>3} {"union":>7} {"maxacc":>7} {"reservoir":>9} {"res%":>6} '
          f'{"unionFDP":>8} {"gain":>7}')
    for (label, n), (name, files, vals) in sorted(found.items(), key=lambda kv: kv[1][1]):
        if n != 1 or (label, 2) not in found:
            continue
        pr = ((M.load(os.path.join(M.RUNS, name)).get('crossRun') or {}).get('perRun') or {})
        cu, uf = pr.get('cumUnion'), pr.get('unionFdp')
        if not cu:
            continue
        union, mx = cu[-1], vals['matched']
        b2 = found[(label, 2)][2]['matched']
        res = union - mx
        gain = 100.0 * (b2 - mx) / mx
        rows.append((label, files, union, mx, res, 100.0 * res / union, 100 * uf[-1], gain))
        print(f'{label:<10} {files:>3} {union:>7} {mx:>7} {res:>9} {100.0*res/union:>5.1f}% '
              f'{100*uf[-1]:>7.2f}% {gain:>+6.1f}%')

    gains = [r[7] for r in rows]
    for idx, nm in ((4, 'reservoir'), (5, 'reservoir %'), (6, 'union FDP'), (1, 'file count')):
        xs = [r[idx] for r in rows]
        print(f'\n{nm:<12} vs gain: Pearson r={pearson(xs, gains):+.2f}  '
              f'Spearman rho={pearson(rank(xs), rank(gains)):+.2f}')
    big = [r for r in rows if r[1] >= 12]
    if len(big) >= 4:
        print(f'\n(F>=12 only, n={len(big)}) reservoir vs gain: '
              f'Pearson r={pearson([r[4] for r in big], [r[7] for r in big]):+.2f}  '
              f'Spearman rho={pearson(rank([r[4] for r in big]), rank([r[7] for r in big])):+.2f}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
