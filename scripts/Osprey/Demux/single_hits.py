"""Are the single-hit profile events vendor centroiding drops fragment signal or noise? For each single-point
profile peak in a sweep's spectrum, is there a kept vendor centroid within PPM in a spectrum within +/- K
encoded bins of the same sweep (where the same precursor's fragments recur)? Compared with the same test at
m/z shifted by +0.37 Th (off any real fragment): a signal hit is far likelier than chance to land on a
fragment that is seen, as a real peak, a few bins away.

Usage: python single_hits.py <profile.mzML> <vendor.mzML> [ppm] [K]
"""
import sys

import numpy as np
from pyteomics import mzml


def spectra(path):
    out = []
    with mzml.MzML(path) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']):
                order = np.argsort(s['m/z array'])
                out.append((s['m/z array'][order], s['intensity array'][order]))
    return out


def single_points(mz, inten):
    rel = np.diff(mz) / mz[:-1]
    cut = np.where(rel > 3 * np.median(rel))[0] + 1
    starts = np.concatenate(([0], cut))
    ends = np.concatenate((cut, [len(mz)]))
    single = (ends - starts) == 1
    return mz[starts[single]]


def near(values, sorted_mz, ppm):
    if len(sorted_mz) == 0 or len(values) == 0:
        return np.zeros(len(values), bool)
    pos = np.searchsorted(sorted_mz, values)
    hit = np.zeros(len(values), bool)
    for off in (-1, 0):
        idx = np.clip(pos + off, 0, len(sorted_mz) - 1)
        hit |= np.abs(sorted_mz[idx] - values) / values * 1e6 <= ppm
    return hit


def main():
    ppm = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    k = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    profile = spectra(sys.argv[1])
    vendor = spectra(sys.argv[2])
    n = min(len(profile), len(vendor))  # the same sweep, in bin order
    real = shifted = total = 0
    for i in range(n):
        singles = single_points(*profile[i])
        others = [vendor[j][0] for j in range(max(0, i - k), min(n, i + k + 1)) if j != i]
        pool = np.sort(np.concatenate(others)) if others else np.array([])
        real += int(near(singles, pool, ppm).sum())
        shifted += int(near(singles + 0.37, pool, ppm).sum())
        total += len(singles)
    print('%d single-hit events over %d spectra; within %.0f ppm of a kept centroid in bins +/- %d:' % (total, n, ppm, k))
    print('  at their own m/z: %.1f%%   shifted +0.37 Th: %.1f%%   enrichment %.2fx'
          % (100 * real / total, 100 * shifted / total, real / max(shifted, 1)))


if __name__ == '__main__':
    main()
