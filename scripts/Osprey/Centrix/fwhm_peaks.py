"""Measures profile peak widths (FWHM) of isolated intense peaks per MS level, for Centrix sigma calibration.

Usage: python fwhm_peaks.py <profile.mzML> [max spectra]

A peak: a local maximum above the spectrum's 99th percentile, whose apex height comes from the log-parabola
through its top three points, and whose intensity falls monotonically to half that height on both sides (no
second peak before the half-maximum crossing). FWHM by linear interpolation of the crossings.
"""
import sys
import numpy as np
from pyteomics import mzml


def widths(mz, y):
    out = []
    thr = max(np.quantile(y, 0.99), 0)
    n = len(y)
    for i in range(1, n - 1):
        if not (y[i] > thr and y[i] > y[i - 1] and y[i] >= y[i + 1] and y[i - 1] > 0 and y[i + 1] > 0):
            continue
        l0, l1, l2 = np.log(y[i - 1:i + 2])
        a = l0 - 2 * l1 + l2
        top = y[i]
        if a < 0:
            off = 0.5 * (l0 - l2) / a
            if abs(off) <= 0.5:
                top = np.exp(l1 - 0.25 * (l0 - l2) * off)
        half = top / 2
        L = i
        ok = True
        while L > 0 and y[L - 1] < y[L] and y[L] > half:
            L -= 1
        if y[L] > half:
            ok = False
        R = i
        while ok and R < n - 1 and y[R + 1] < y[R] and y[R] > half:
            R += 1
        if not ok or y[R] > half:
            continue
        xl = mz[L] + (half - y[L]) / (y[L + 1] - y[L]) * (mz[L + 1] - mz[L])
        xr = mz[R - 1] + (y[R - 1] - half) / (y[R - 1] - y[R]) * (mz[R] - mz[R - 1])
        out.append(xr - xl)
    return out


def main():
    path = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
    by_level = {1: [], 2: []}
    spectra = {1: 0, 2: 0}
    with mzml.MzML(path) as reader:
        for k, s in enumerate(reader):
            if k >= limit:
                break
            level = s['ms level']
            if level not in by_level:
                continue
            spectra[level] += 1
            by_level[level].extend(widths(np.asarray(s['m/z array'], float), np.asarray(s['intensity array'], float)))
    for level, w in by_level.items():
        if not w:
            continue
        w = np.array(w)
        q = np.percentile(w, [10, 25, 50, 75, 90])
        print('MS%d: %d spectra, %d peaks; FWHM p10 %.3f p25 %.3f median %.3f p75 %.3f p90 %.3f Th; sigma (median) %.3f Th'
              % (level, spectra[level], len(w), *q, q[2] / 2.3548))


if __name__ == '__main__':
    main()
