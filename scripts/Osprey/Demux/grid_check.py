"""Is the ZT Scan TOF profile on one uniform grid? From a profile dump (zero points dropped):
1. Within each MS2 spectrum: the step in sqrt(m/z) between consecutive points (the smallest gaps are one sample);
   every point's offset from the nearest integer sample index on sqrt(m/z) = r0 + k * step, which is ~0 for a
   grid uniform in flight time.
2. Across spectra: whether the points of different spectra fall on the same samples: the fractional sample
   position of each spectrum's grid origin, and the share of one spectrum's m/z values found exactly (1e-7 ppm)
   in another's.

Usage: python grid_check.py <profile.mzML>
"""
import sys

import numpy as np
from pyteomics import mzml


def main():
    ms2 = []
    with mzml.MzML(sys.argv[1]) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']) > 100:
                ms2.append((s['id'], np.sort(s['m/z array'])))
    print('%d MS2 profile spectra' % len(ms2))

    # 1. Step in sqrt(m/z) and fit to an integer grid, per spectrum.
    steps, origins, rms = [], [], []
    for sid, mz in ms2:
        r = np.sqrt(mz)
        gaps = np.diff(r)
        gaps = gaps[gaps > 0]
        step0 = np.percentile(gaps, 5)  # adjacent samples
        # Refine: take gaps within 20% of one step, their median is the step.
        step = np.median(gaps[np.abs(gaps / step0 - 1) < 0.2])
        k = np.round((r - r[0]) / step)
        # Least squares r = r0 + k * step on the integer indices.
        A = np.vstack([np.ones_like(k), k]).T
        (r0, st), *_ = np.linalg.lstsq(A, r, rcond=None)
        resid = r - (r0 + k * st)
        steps.append(st)
        origins.append(r0)
        rms.append(np.sqrt(np.mean((resid / st) ** 2)))
    steps, origins, rms = np.array(steps), np.array(origins), np.array(rms)
    print('sqrt(m/z) step: median %.6e, relative spread across spectra (max-min)/median %.2e'
          % (np.median(steps), (steps.max() - steps.min()) / np.median(steps)))
    print('fit residual in samples (rms per spectrum): median %.4f, max %.4f' % (np.median(rms), rms.max()))
    step = np.median(steps)
    print('step as m/z at 400 / 700 / 1200: %.5f / %.5f / %.5f Th (%.1f / %.1f / %.1f ppm)'
          % tuple([2 * np.sqrt(m) * step for m in (400, 700, 1200)] + [2 * step / np.sqrt(m) * 1e6 for m in (400, 700, 1200)]))

    # 2. Shared grid across spectra: each origin's fractional position on spectrum 0's grid.
    base_r0 = origins[0]
    frac = ((origins - base_r0) / step) % 1.0
    frac = np.minimum(frac, 1 - frac)
    print('grid origin offset from spectrum 0, in samples: median %.4f, max %.4f' % (np.median(frac), frac.max()))
    exact = []
    for i in range(1, min(len(ms2), 40)):
        a, b = ms2[0][1], ms2[i][1]
        pos = np.clip(np.searchsorted(b, a), 1, len(b) - 1)
        d = np.minimum(np.abs(b[pos] - a), np.abs(b[pos - 1] - a)) / a
        near = d < 0.5 * step / np.sqrt(a) * 2  # within half a sample
        exact.append((np.mean(d[near] < 1e-13), near.sum()))
    share = np.array([e[0] for e in exact])
    print('of points within half a sample of a point in another spectrum, share at the identical m/z (1e-13): '
          'median %.3f, min %.3f' % (np.median(share), share.min()))


if __name__ == '__main__':
    main()
