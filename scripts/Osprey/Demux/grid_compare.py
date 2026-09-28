"""Whether profile dumps from different sweeps and runs share one TOF grid: per file, the sqrt(m/z) step, and the
offset of every point from the reference file's grid (r0_ref + k * step_ref), in samples.

Usage: python grid_compare.py <reference profile.mzML> <other profile.mzML> [...]
"""
import sys

import numpy as np
from pyteomics import mzml


def roots(path):
    out = []
    with mzml.MzML(path) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']) > 100:
                out.append(np.sqrt(np.sort(s['m/z array'])))
    return out


def step_of(r):
    gaps = np.diff(r)
    gaps = gaps[gaps > 0]
    step0 = np.percentile(gaps, 5)
    return np.median(gaps[np.abs(gaps / step0 - 1) < 0.2])


def main():
    ref = roots(sys.argv[1])
    step = np.median([step_of(r) for r in ref])
    r0 = ref[0][0]
    print('reference %s: %d spectra, step %.9e' % (sys.argv[1], len(ref), step))
    for path in sys.argv[2:]:
        other = roots(path)
        steps = np.array([step_of(r) for r in other])
        allr = np.concatenate(other)
        frac = (allr - r0) / step
        off = frac - np.round(frac)
        print('%s: %d spectra, step %.9e (ratio to reference - 1: %.2e); offset from the reference grid in samples: '
              'median %+.5f, max |.| %.5f' % (path, len(other), np.median(steps), np.median(steps) / step - 1,
                                              np.median(off), np.abs(off).max()))


if __name__ == '__main__':
    main()
