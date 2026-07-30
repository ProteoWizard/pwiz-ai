#!/usr/bin/env python3
"""Does max's k=1 slice FDP actually predict the best-2 gain? Check it against EVERY cohort,
not the subset that was in view when the idea formed (4/20/40/60/82). Reports Pearson and
Spearman over all cohorts, and again with the largest two dropped, since a single extreme
point can carry a correlation on its own.
"""
import csv
import os
import statistics as st


def rank(vals):
    order = sorted(range(len(vals)), key=lambda i: vals[i])
    r = [0.0] * len(vals)
    i = 0
    while i < len(order):                       # average ranks within ties
        j = i
        while j + 1 < len(order) and vals[order[j + 1]] == vals[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1
        for k in range(i, j + 1):
            r[order[k]] = avg
        i = j + 1
    return r


def pearson(x, y):
    mx, my = st.mean(x), st.mean(y)
    num = sum((a - mx) * (b - my) for a, b in zip(x, y))
    den = (sum((a - mx) ** 2 for a in x) * sum((b - my) ** 2 for b in y)) ** 0.5
    return num / den if den else float('nan')


import mbn_surface as M                                                          # noqa: E402

with open(os.path.join(M.OUT, 'mbn_surface.csv'), encoding='utf-8') as fh:
    rows = list(csv.DictReader(fh))
pts = []
for r in rows:
    if r['N'] != '2' or not r['gain_pct']:
        continue
    mx = next((q for q in rows if q['cohort'] == r['cohort'] and q['N'] == '1'), None)
    if not mx or not mx['k1_fdp_pct']:
        continue
    pts.append((r['cohort'], int(r['F']), float(mx['k1_fdp_pct']), float(r['gain_pct']),
                float(mx['fdp_q1_pct'])))

pts.sort(key=lambda p: p[2])
print(f'{"cohort":<10} {"F":>3} {"max k1FDP":>9} {"gain":>7} {"max trueFDP@1%q":>16}')
for c, f, k1, g, fdp in pts:
    print(f'{c:<10} {f:>3} {k1:>8.2f}% {g:>+6.1f}% {fdp:>15.3f}%')

k1 = [p[2] for p in pts]
gain = [p[3] for p in pts]
print(f'\nall {len(pts)} cohorts:      Pearson r={pearson(k1, gain):+.2f}   '
      f'Spearman rho={pearson(rank(k1), rank(gain)):+.2f}')
small = [p for p in pts if p[1] <= 60]
print(f'dropping F>60 ({len(small)}):     Pearson r={pearson([p[2] for p in small], [p[3] for p in small]):+.2f}   '
      f'Spearman rho={pearson(rank([p[2] for p in small]), rank([p[3] for p in small])):+.2f}')
mid = [p for p in pts if 12 <= p[1] <= 82]
print(f'F>=12 only ({len(mid)}):        Pearson r={pearson([p[2] for p in mid], [p[3] for p in mid]):+.2f}   '
      f'Spearman rho={pearson(rank([p[2] for p in mid]), rank([p[3] for p in mid])):+.2f}')

# Calibration of the max baseline is the other candidate signal at the high end.
fdp = [p[4] for p in pts]
print(f'\nmax trueFDP@1%q vs gain:  Pearson r={pearson(fdp, gain):+.2f}   '
      f'Spearman rho={pearson(rank(fdp), rank(gain)):+.2f}')
