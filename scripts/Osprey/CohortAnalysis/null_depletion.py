#!/usr/bin/env python3
"""Null-population depletion between pass 1 and pass 2, straight from the diagnostics payload.

The 2nd-pass distribution plots are where a depleted or selection-conditioned null shows itself:
if the decoy population shrinks faster than the target population between passes, the q that the
2nd pass derives is resting on a thinner - and differently selected - null than the one that
calibrated pass 1.

Usage: python null_depletion.py [run-dir-name ...]
"""
import os
import sys

import mbn_surface as M

DIRS = sys.argv[1:] or ['pass2-82-4way-protein-compact', 'pass2-82-4way-transfer-compete']


def line(tag, d):
    sc = d.get('scores') or {}
    return (f'    {tag:<6} target {d.get("nTarget") or 0:>9,}  decoy {d.get("nDecoy") or 0:>9,}  '
            f'p_target {d.get("npTarget") or 0:>9,}  p_decoy {d.get("npDecoy") or 0:>9,}  '
            f'decoyN {sc.get("decoyN") or 0:>9,}  decoyMean '
            f'{sc.get("decoyMean") if sc.get("decoyMean") is not None else float("nan"):>8.3f}')


def equal_chance(tag, d):
    """The two shipped tripwires (PR #4399).

    winFraction = the paired coin: among pairs in the NULL BAND, how often does the target beat
    its own decoy? Honest equal-chance sits at ~50%. A collapse means targets are systematically
    beating their paired decoys there - the signature of a selection-conditioned or boosted target
    population, which reads as anti-conservative FDR.
    densityRatio.plateauRatio = the pi0 / false-fraction readout; flatnessSlope says whether
    equal-chance still holds across the null region.
    """
    def scalar(v):
        """These fields are per-bin arrays in some payloads and scalars in others."""
        if isinstance(v, list):
            return sum(x for x in v if isinstance(x, (int, float))) if v else None
        return v

    wf = d.get('winFraction') or {}
    dr = d.get('densityRatio') or {}
    real = scalar(wf.get('nullBandReal'))
    ent = scalar(wf.get('nullBandEnt'))
    out = [f'    {tag:<6}']
    out.append(f'coin(real) {100 * real:5.1f}%' if isinstance(real, float) else 'coin(real)   n/a')
    out.append(f'coin(entrap) {100 * ent:5.1f}%' if isinstance(ent, float) else 'coin(entrap)   n/a')
    out.append(f'realN {scalar(wf.get("realN")) or 0:>9,.0f}  '
               f'entN {scalar(wf.get("entN")) or 0:>8,.0f}')
    if dr.get('plateauRatio') is not None:
        out.append(f'plateau {dr["plateauRatio"]:.3f}')
    if dr.get('flatnessSlope') is not None:
        out.append(f'flatness {dr["flatnessSlope"]:+.4f}')
    return '  '.join(out)


for name in DIRS:
    j = M.load(os.path.join(M.RUNS, name))
    if not j:
        print(f'--- {name}: unreadable')
        continue
    p2 = j.get('pass2') or {}
    print(f'--- {name}')
    print(line('pass1', j))
    print(equal_chance('pass1', j))
    if p2:
        print(equal_chance('pass2', p2))
        print(line('pass2', p2))
        t1, d1 = j.get('nTarget') or 0, j.get('nDecoy') or 0
        t2, d2 = p2.get('nTarget') or 0, p2.get('nDecoy') or 0
        if t1 and d1 and t2 and d2:
            print(f'    kept into pass 2: targets {100.0 * t2 / t1:5.1f}%   '
                  f'decoys {100.0 * d2 / d1:5.1f}%   '
                  f'-> decoy:target ratio {d1 / t1:.3f} (pass1) -> {d2 / t2:.3f} (pass2)')
            if (d2 / t2) < (d1 / t1):
                print(f'    NULL DEPLETED: the pass-2 competition sees '
                      f'{100 * (1 - (d2 / t2) / (d1 / t1)):.1f}% fewer decoys per target')
