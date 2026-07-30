#!/usr/bin/env python3
"""Detect the FDRBench Figure-4a plateau: estimated FDP that stops tracking the FDR threshold.

When a method re-derives q on a pool that a FIRST-PASS q cut already selected, the reported q
loses resolution inside that pool: sweeping the nominal threshold returns nearly the same set, so
true FDP flattens at whatever the first-pass filter admitted. Wen et al. Fig 4a shows this for
EncyclopeDIA (flat ~1.3% across 0-5%) and Spectronaut (flat ~1.3% within 0.002%), while DIA-NN
rises with the threshold. A calibrated method tracks the diagonal: FDP(t) ~= t, slope ~1.

Reports, per arm and pass, the estimated FDP at a ladder of thresholds plus:
  slope   d(FDP)/d(threshold) over 1%->5%; ~1 tracks, ~0 is a plateau
  ratio   FDP(1%) / 1%; the overconfidence factor at the operating point

Usage: python plateau_check.py [run-dir ...]
"""
import os
import sys

import mbn_surface as M

RUNS_DEFAULT = ['pass2-82-4way-protein-compact', 'pass2-82-4way-transfer-compete']
LADDER = [0.001, 0.0025, 0.005, 0.01, 0.02, 0.05]


def curve(view):
    """[(threshold, estimated FDP, accepted)] for the ladder, from an fdpView.

    A threshold beyond the reported q range yields None rather than the last in-range point.
    Without this the curve looks FLAT past its own end and a well-calibrated arm reads as a
    plateau - pass-1 fdpViews stop near 2%, so the 5% rung is simply not measured.
    """
    q, comb, disc = view['q'], view['combined'], view['nTargetAccepted']
    qmax = max(q) if q else 0.0
    out = []
    for t in LADDER:
        if t > qmax + 1e-12:                      # not measured; do NOT extrapolate
            out.append((t, None, None))
            continue
        idx = [i for i in range(len(q)) if q[i] <= t + 1e-12]
        i = max(idx, key=lambda k: disc[k])
        out.append((t, 100 * comb[i], disc[i]))
    return out


def report(label, view):
    rows = curve(view)
    cells = '  '.join(f'{t:.2%}:{f:5.2f}%' if f is not None else f'{t:.2%}:  -  '
                      for t, f, _ in rows)
    print(f'  {label:<34} {cells}')
    at1 = next((f for t, f, _ in rows if abs(t - 0.01) < 1e-9), None)
    # Judge SEGMENT BY SEGMENT. A plateau is flat FDP while THAT SAME segment still gains
    # discoveries. Averaging a slope across the whole range mixes a tracking segment with a
    # frozen one and manufactures a plateau - which is how this detector twice misread Osprey's
    # own well-calibrated pass 1, whose set stops growing above 2% because the reported pool is
    # q-filtered.
    pts = [(t, f, d) for t, f, d in rows if f is not None]
    segs, flat_disc, live_disc = [], 0, 0
    for (t0, f0, d0), (t1, f1, d1) in zip(pts, pts[1:]):
        gain = d1 - d0
        if gain <= max(50, 0.01 * d0):                 # set effectively frozen here
            segs.append(f'{t0:.2%}-{t1:.2%} frozen')
            continue
        slope = (f1 - f0) / (100 * (t1 - t0))
        segs.append(f'{t0:.2%}-{t1:.2%} slope {slope:.2f} (+{gain:,})')
        live_disc += gain
        if slope < 0.25:
            flat_disc += gain
    if at1 is not None:
        print(f'  {"":<34} overconfidence at 1% {at1:4.2f}x')
    print(f'  {"":<34} ' + ' | '.join(segs))
    if live_disc == 0:
        print(f'  {"":<34} -> no segment gains discoveries; flatness NOT informative '
              f'(reported pool truncated)')
    elif flat_disc / live_disc > 0.5:
        print(f'  {"":<34} -> PLATEAU: {100 * flat_disc / live_disc:.0f}% of new discoveries '
              f'arrive while FDP stays flat')
    else:
        print(f'  {"":<34} -> tracks the threshold where the set still grows')


def main():
    dirs = sys.argv[1:] or RUNS_DEFAULT
    print('estimated true FDP at each nominal FDR threshold (experiment scope)')
    for name in dirs:
        j = M.load(os.path.join(M.RUNS, name))
        if not j:
            print(f'--- {name}: unreadable')
            continue
        print(f'--- {name}')
        v1 = [v for v in (j.get('fdpViews') or []) if v.get('scope') == 'experiment']
        if v1:
            report('pass 1 (first-pass experiment q)', v1[0])
        v2 = [v for v in ((j.get('pass2') or {}).get('fdpViews') or [])
              if v.get('scope') == 'experiment']
        if v2:
            report('pass 2 (this mode)', v2[0])
        else:
            print('  pass 2: no experiment fdpView')


if __name__ == '__main__':
    raise SystemExit(main())
