#!/usr/bin/env python3
"""Is mean(best-2) a STABILISER rather than just a booster?

Nested contiguous cohorts (files 1-20 / 1-28 / 1-30 / 1-40) give max = 46,496 / 41,623 / 45,832 /
47,290 but best-2 = 47,685 / 47,617 / 48,431 / 48,672. The max baseline has a 10% hole at 28 files
that best-2 does not. If that generalises, the "gain" mostly measures how badly max happened to
underperform on a given cohort - which would explain why no cohort property predicts it.

Both arms are normalised by that cohort's accepted UNION (aggregation-independent, verified
byte-identical between arms), so cohorts of different size and quality are comparable. The
question is whether yield/union scatters less under best-2 than under max.
"""
import os
import statistics as st

import mbn_surface as M
from mechanism import arms

found = arms()
rows = []
for (label, n) in list(found):
    if n != 1 or (label, 2) not in found:
        continue
    na, files, _ = found[(label, 1)]
    cu = ((M.load(os.path.join(M.RUNS, na)).get('crossRun') or {}).get('perRun') or {}).get('cumUnion')
    if not cu:
        continue
    mx = M.metrics(os.path.join(M.RUNS, na))['matched']
    b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
    rows.append((label, files, mx, b2, cu[-1], 100.0 * mx / cu[-1], 100.0 * b2 / cu[-1]))

rows.sort(key=lambda r: r[1])
print(f'{"cohort":<10} {"F":>3} {"union":>6} {"max/union":>10} {"best2/union":>12} {"gain":>7}')
for r in rows:
    print(f'{r[0]:<10} {r[1]:>3} {r[4]:>6} {r[5]:>9.1f}% {r[6]:>11.1f}% '
          f'{100.0*(r[3]-r[2])/r[2]:>+6.1f}%')

for lo, hi, nm in ((0, 999, 'all cohorts'), (15, 45, 'mid-size only (15-45 files)')):
    sub = [r for r in rows if lo <= r[1] <= hi]
    if len(sub) < 3:
        continue
    a = [r[5] for r in sub]
    b = [r[6] for r in sub]
    print(f'\n{nm} (n={len(sub)}):')
    print(f'  max/union    mean {st.mean(a):5.1f}%  sd {st.pstdev(a):4.2f}  '
          f'range {min(a):.1f}-{max(a):.1f}  CV {100*st.pstdev(a)/st.mean(a):4.1f}%')
    print(f'  best2/union  mean {st.mean(b):5.1f}%  sd {st.pstdev(b):4.2f}  '
          f'range {min(b):.1f}-{max(b):.1f}  CV {100*st.pstdev(b)/st.mean(b):4.1f}%')
    print(f'  -> best-2 scatter is {st.pstdev(a)/st.pstdev(b):.2f}x '
          f'{"SMALLER" if st.pstdev(b) < st.pstdev(a) else "LARGER"} than max')

# The nested contiguous series is the cleanest demonstration: same files plus a few more.
nested = [r for r in rows if r[0] in ('4', '5', '6', '8', '10', '12', '17', '20', '28', '30',
                                      '40', '60', '82')]
if len(nested) >= 4:
    a = [r[5] for r in nested]
    b = [r[6] for r in nested]
    print(f'\nnested contiguous series only (n={len(nested)}): '
          f'max/union sd {st.pstdev(a):.2f} vs best2/union sd {st.pstdev(b):.2f}')
