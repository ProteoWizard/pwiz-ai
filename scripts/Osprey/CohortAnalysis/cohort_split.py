#!/usr/bin/env python3
"""Where do the weak files sit in the sorted order? Cohorts are the FIRST F files by name,
so any group that sorts to the end (e.g. pooled QC samples) only enters at large F -- which
would confound "cohort size" with "cohort content". Reads the 82-file max arm's per-file table.
"""
import os
import statistics as st

import mbn_surface as M

d = M.load(os.path.join(M.RUNS, 'pass2ab-82file-percolator-5day'))
pf = d['perFile']


def rate(r):
    return 10000.0 * r['entrapment'] / max(1, r['targets'])


print('idx  file-key             targets  entrap/10k')
for i, r in enumerate(pf, 1):
    if i <= 3 or 39 <= i <= 44 or i >= 76:
        key = r['file'].split('SEA-AD-')[-1][:18]
        print(f'{i:>3}  {key:<20} {r["targets"]:>7,}  {rate(r):5.1f}')

pools = [r for r in pf if 'pool' in r['file'].lower()]
donors = [r for r in pf if 'pool' not in r['file'].lower()]
groups = (('donors', donors), ('pools', pools),
          ('files 1-40', pf[:40]), ('files 41-82', pf[40:]),
          ('files 41-82 donors', [r for r in pf[40:] if 'pool' not in r['file'].lower()]))
print()
for name, grp in groups:
    if not grp:
        continue
    t = [r['targets'] for r in grp]
    e = [rate(r) for r in grp]
    print(f'{name:<20} n={len(grp):>3}  targets median {st.median(t):>7,.0f}  mean {st.mean(t):>7,.0f}'
          f'   min {min(t):>7,}   entrap/10k median {st.median(e):5.1f}')

print('\npool file positions in the sorted order:',
      [i for i, r in enumerate(pf, 1) if 'pool' in r['file'].lower()])
