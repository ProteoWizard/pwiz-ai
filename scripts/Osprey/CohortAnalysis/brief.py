#!/usr/bin/env python3
"""Compact one-line-per-cohort harvest, for night-session context economy.

Full detail stays in mbn_surface.csv / mechanism.txt; this prints only what a checkpoint needs.
Optional args filter cohorts by substring: python brief.py spread f10 f20
"""
import os
import sys

import mbn_surface as M

pats = [a.lower() for a in sys.argv[1:]]
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
    found.setdefault((label, n), (files, vals))

rows = []
for (label, n), (files, vals) in found.items():
    if n != 1:
        continue
    base = vals['matched']
    for n2 in sorted({k[1] for k in found if k[0] == label} - {1}):
        v2 = found[(label, n2)][1]
        rows.append((label, files, n2, base, v2['matched'],
                     100.0 * (v2['matched'] - base) / base, vals['k1_fdp'], vals['fdp_q1'] * 100))
    if not any(k[0] == label and k[1] != 1 for k in found):
        rows.append((label, files, None, base, None, None, vals['k1_fdp'], vals['fdp_q1'] * 100))

rows = [r for r in rows if not pats or any(p in r[0].lower() for p in pats)]
for r in sorted(rows, key=lambda r: (r[1], r[0], r[2] or 0)):
    n2 = f'best-{r[2]}' if r[2] else 'max only'
    got = f'{r[4]:>6}' if r[4] else '     -'
    gain = f'{r[5]:+6.1f}%' if r[5] is not None else '      '
    print(f'{r[0]:<10} F={r[1]:<3} {n2:<7} max {r[3]:>6} -> {got} {gain}'
          f'   maxk1FDP {r[6]:5.2f}%  maxq1trueFDP {r[7]:.3f}%')
print(f'({len(rows)} comparisons)')
