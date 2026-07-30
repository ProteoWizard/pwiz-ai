#!/usr/bin/env python3
"""Side-by-side k-structure for named cohorts: accepted-set shape under max, and where
mean(best-2) moves acceptances. Usage: python kcompare.py [cohort ...]  (default: a fixed set)
"""
import os
import sys

import mbn_surface as M
from mechanism import arms, k_slices

want = [a.lower() for a in sys.argv[1:]] or ['spread17', 'spread41', '20', '40', '60', '82']
found = arms()
print(f'{"cohort":<10} {"F":>3} {"union":>6} {"maxacc":>6} {"eff":>5}  '
      f'{"k=1sh":>6} {"k>=6sh":>7}  {"dk=1":>6} {"dk=2":>6} {"dk3-5":>6} {"dk>=6":>6} {"gain":>7}')
for label in sorted({k[0] for k in found}, key=lambda s: found[(s, 1)][1] if (s, 1) in found else 0):
    if label.lower() not in want or (label, 1) not in found or (label, 2) not in found:
        continue
    na, files, _ = found[(label, 1)]
    nb = found[(label, 2)][0]
    da, db = M.load(os.path.join(M.RUNS, na)), M.load(os.path.join(M.RUNS, nb))
    ka = k_slices((da.get('crossRun') or {}).get('experiment') or {})
    kb = k_slices((db.get('crossRun') or {}).get('experiment') or {})
    cu = ((da.get('crossRun') or {}).get('perRun') or {}).get('cumUnion') or [0]
    mx = M.metrics(os.path.join(M.RUNS, na))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, nb))['matched']
    d = {k: kb[k][0] - ka[k][0] for k in ka}
    eff = 100.0 * mx / cu[-1] if cu[-1] else 0
    print(f'{label:<10} {files:>3} {cu[-1]:>6} {mx:>6} {eff:>4.0f}%  '
          f'{ka["k=1"][1]:>5.1f}% {ka["k>=6"][1]:>6.1f}%  {d["k=1"]:>+6} {d["k=2"]:>+6} '
          f'{d["k=3-5"]:>+6} {d["k>=6"]:>+6} {100.0*(b2-mx)/mx:>+6.1f}%')
