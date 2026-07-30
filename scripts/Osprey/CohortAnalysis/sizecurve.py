#!/usr/bin/env python3
"""Gains grouped by cohort size, with the replicate spread at each size.

The headline question for any effect-size claim is not "what did cohort X give" but "how much do
cohorts of the same size disagree". This prints every measured cohort by file count, so a single
number is always seen next to its siblings.

Usage: python sizecurve.py
"""
import os
import statistics as st

import mbn_surface as M
from mechanism import arms

found = arms()
by_size = {}
for (label, n), (name, files, kind) in found.items():
    if n != 1 or (label, 2) not in found:
        continue
    mx = M.metrics(os.path.join(M.RUNS, name))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
    by_size.setdefault(files, []).append((label, 100.0 * (b2 - mx) / mx, mx, b2))

print(f'{"F":>4} {"n":>2}  {"mean":>6} {"spread":>7}   cohorts (gain)')
allg = []
for f in sorted(by_size):
    rows = sorted(by_size[f], key=lambda r: r[1])
    g = [r[1] for r in rows]
    allg.extend(g)
    spread = f'{max(g) - min(g):6.1f}' if len(g) > 1 else '     -'
    cells = ', '.join(f'{lab} {v:+.1f}%' for lab, v, _, _ in rows)
    print(f'{f:>4} {len(g):>2}  {st.mean(g):>+5.1f}% {spread}   {cells}')

print(f'\nall {len(allg)} cohort comparisons: median {st.median(allg):+.1f}%, '
      f'range {min(allg):+.1f}% to {max(allg):+.1f}%')
multi = {f: v for f, v in by_size.items() if len(v) > 1}
if multi:
    spreads = {f: max(x[1] for x in v) - min(x[1] for x in v) for f, v in multi.items()}
    print('within-size spread where replicated: '
          + ', '.join(f'F={f}: {s:.1f} pts (n={len(multi[f])})' for f, s in sorted(spreads.items())))
    print(f'-> the largest within-size spread ({max(spreads.values()):.1f} pts) is '
          f'{"LARGER" if max(spreads.values()) > (max(allg) - min(allg)) / 2 else "smaller"} '
          f'than half the total range across all sizes ({(max(allg) - min(allg)) / 2:.1f} pts)')
