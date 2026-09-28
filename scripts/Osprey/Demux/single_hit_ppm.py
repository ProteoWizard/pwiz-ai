"""The m/z precision of single-hit events on real fragments: for each single-point profile peak, the signed
ppm offset to the nearest kept vendor centroid in spectra within +/- K bins of the same sweep, histogrammed
for the events' own m/z and for m/z shifted +0.37 Th (chance). The excess over chance is the single hits
that belong to a fragment; its spread is their m/z precision.

Usage: python single_hit_ppm.py <profile.mzML> <vendor.mzML> [K]
"""
import sys

import numpy as np

from single_hits import single_points, spectra


def offsets(values, pool):
    pos = np.searchsorted(pool, values)
    best = np.full(len(values), np.inf)
    for off in (-1, 0):
        idx = np.clip(pos + off, 0, len(pool) - 1)
        d = (values - pool[idx]) / values * 1e6
        better = np.abs(d) < np.abs(best)
        best[better] = d[better]
    return best


def main():
    k = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    profile = spectra(sys.argv[1])
    vendor = spectra(sys.argv[2])
    n = min(len(profile), len(vendor))
    own, shifted = [], []
    for i in range(n):
        singles = single_points(*profile[i])
        others = [vendor[j][0] for j in range(max(0, i - k), min(n, i + k + 1)) if j != i]
        pool = np.sort(np.concatenate(others))
        own.append(offsets(singles, pool))
        shifted.append(offsets(singles + 0.37, pool))
    own, shifted = np.concatenate(own), np.concatenate(shifted)
    edges = np.arange(-30, 31, 2.5)
    ho, _ = np.histogram(own, edges)
    hs, _ = np.histogram(shifted, edges)
    excess = ho - hs
    print('%10s %8s %8s %8s' % ('ppm', 'own', 'chance', 'excess'))
    for lo, a, b, e in zip(edges[:-1], ho, hs, excess):
        print('%+5.1f..%+5.1f %8d %8d %8d %s' % (lo, lo + 2.5, a, b, e, '#' * max(0, int(e / max(excess.max(), 1) * 40))))
    centers = edges[:-1] + 1.25
    pos = np.clip(excess, 0, None)
    within = [pos[np.abs(centers) <= w].sum() / pos.sum() for w in (5, 10, 15, 20)]
    print('share of the excess within 5 / 10 / 15 / 20 ppm: %.2f / %.2f / %.2f / %.2f' % tuple(within))


if __name__ == '__main__':
    main()
