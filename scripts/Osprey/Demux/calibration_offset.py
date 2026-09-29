"""Per-run m/z offset between the TOF profile (as the SDK reports it without vendor centroiding) and the vendor
centroids of the same spectra: strong profile peaks (contiguous runs, >= MIN counts) matched to the nearest
vendor centroid within 30 ppm; the median signed ppm offset and its spread, by m/z range.

Usage: python calibration_offset.py <profile.mzML> <vendor mzML> [min counts]
The vendor file may be a whole-run mzML: spectra are matched by id.
"""
import sys

import numpy as np
from pyteomics import mzml


def main():
    min_counts = float(sys.argv[3]) if len(sys.argv) > 3 else 3000
    prof = {}
    with mzml.MzML(sys.argv[1]) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']) > 100:
                prof[s['id']] = (s['m/z array'], s['intensity array'])
    vendor = mzml.PreIndexedMzML(sys.argv[2])
    offs, mzs = [], []
    for sid, (mz, it) in prof.items():
        try:
            v = vendor.get_by_id(sid)
        except KeyError:
            continue
        vmz = np.sort(v['m/z array'])
        order = np.argsort(mz)
        mz, it = mz[order], it[order]
        rel = np.diff(np.sqrt(mz))
        cut = np.where(rel > 1.5 * np.median(rel))[0] + 1
        for sm, si in zip(np.split(mz, cut), np.split(it, cut)):
            if si.sum() < min_counts:
                continue
            c = np.sum(sm * si) / si.sum()
            j = np.searchsorted(vmz, c)
            cand = [vmz[k] for k in (j - 1, j) if 0 <= k < len(vmz)]
            best = min(cand, key=lambda x: abs(x - c))
            d = (c - best) / best * 1e6
            if abs(d) <= 30:
                offs.append(d)
                mzs.append(c)
    offs, mzs = np.array(offs), np.array(mzs)
    print('%s: %d strong peaks matched; profile - vendor: median %+.2f ppm (p25 %+.2f, p75 %+.2f)'
          % (sys.argv[1], len(offs), np.median(offs), *np.percentile(offs, [25, 75])))
    for lo, hi in ((150, 400), (400, 700), (700, 1000), (1000, 1600)):
        sel = (mzs >= lo) & (mzs < hi)
        if sel.sum() > 20:
            print('  m/z %4d-%4d: n %5d, median %+.2f ppm' % (lo, hi, sel.sum(), np.median(offs[sel])))


if __name__ == '__main__':
    main()
