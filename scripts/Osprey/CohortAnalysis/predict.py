#!/usr/bin/env python3
"""Pre-register a two-factor prediction for a cohort from its MAX arm alone.

gain% ~= 82.8 * (A * B) - 1.24     (fit over 20 cohorts, mean |residual| 1.85 pts)
  A = share of accepted FALSE hits resting on a single run  (what mean(best-2) can remove)
  B = (union - accepted) / union                            (reservoir available to backfill)

Both come from the max arm, so the prediction is made BEFORE the best-2 arm of that cohort
finishes - an honest out-of-sample test rather than a refit. Prints the actual too, when present.

Usage: python ai/.tmp/predict.py [cohort ...]     (default: every cohort with a max arm)
"""
import os
import sys

import mbn_surface as M
from mechanism import arms

A_COEF, INTERCEPT = 82.8, -1.24
want = [a.lower() for a in sys.argv[1:]]
found = arms()

print(f'{"cohort":<10} {"F":>3} {"A":>6} {"B":>6} {"predicted":>10} {"actual":>8} {"err":>7}')
for label in sorted({k[0] for k in found}, key=lambda s: found[(s, 1)][1] if (s, 1) in found else 0):
    if (label, 1) not in found or (want and label.lower() not in want):
        continue
    na, files, _ = found[(label, 1)]
    d = M.load(os.path.join(M.RUNS, na))
    exp = (d.get('crossRun') or {}).get('experiment') or {}
    eh = exp.get('entrapmentRunCountHistogram') or []
    cu = ((d.get('crossRun') or {}).get('perRun') or {}).get('cumUnion') or [0]
    if not eh or not cu[-1]:
        continue
    mx = M.metrics(os.path.join(M.RUNS, na))['matched']
    a_fac = eh[0] / sum(eh)
    b_fac = (cu[-1] - mx) / cu[-1]
    pred = INTERCEPT + A_COEF * a_fac * b_fac
    act, err = '', ''
    if (label, 2) in found:
        b2 = M.metrics(os.path.join(M.RUNS, found[(label, 2)][0]))['matched']
        gain = 100.0 * (b2 - mx) / mx
        act = f'{gain:+.1f}%'
        err = f'{gain - pred:+.1f}'
    print(f'{label:<10} {files:>3} {a_fac:>6.3f} {b_fac:>6.3f} {pred:>+9.1f}% {act:>8} {err:>7}')
