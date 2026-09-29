"""Measure the ZT Scan quadrupole transmission kernel from the data (spec section 2.4).

Probes are intense MS1 peaks. In the MS2 sweep that follows each MS1 scan, a probe's own m/z
survives unfragmented in every encoded bin whose quadrupole position transmits it, so its
intensity against (bin center - probe m/z) traces the transmission profile. No identifications
are needed.

Usage: python Measure-ZtScanKernel.py <run.mzML> <out_prefix> [rt_min rt_max]
Writes <out_prefix>.profile.tsv (median normalized profile per 0.25 Th offset, overall and by
m/z range) and prints the FWHM, center shift and tail asymmetry.
"""
import bisect
import math
import sys
from collections import defaultdict

import numpy as np
from pyteomics import mzml

PPM = 15.0            # probe m/z tolerance in each MS2 bin
TOP_N = 40            # probes per MS1 scan
MZ_LO, MZ_HI = 405.0, 885.0   # keep probes away from the sweep ends
MAX_OFFSET = 20.0     # Th either side of the probe
STEP = 0.25           # Th per profile bin
MIN_PEAK_RATIO = 10.0  # probe profile max over its median, to reject noise


def main():
    path, prefix = sys.argv[1], sys.argv[2]
    rt_lo = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    rt_hi = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9

    nbins = int(2 * MAX_OFFSET / STEP) + 1
    groups = {'all': [], 'low (405-565)': [], 'mid (565-725)': [], 'high (725-885)': []}
    centers_seen = []

    def group_of(mz):
        if mz < 565:
            return 'low (405-565)'
        if mz < 725:
            return 'mid (565-725)'
        return 'high (725-885)'

    def flush(ms1, sweep):
        if ms1 is None or len(sweep) < 400:
            return
        mzs1, ints1 = ms1
        keep = (mzs1 > MZ_LO) & (mzs1 < MZ_HI)
        if not keep.any():
            return
        idx = np.argsort(ints1[keep])[::-1][:TOP_N]
        probes = mzs1[keep][idx]
        centers = np.array([c for c, _, _ in sweep])
        for m in probes:
            tol = m * PPM * 1e-6
            near = np.where(np.abs(centers - m) <= MAX_OFFSET)[0]
            if len(near) < 20:
                continue
            prof = []
            for k in near:
                c, smz, sint = sweep[k]
                lo = bisect.bisect_left(smz, m - tol)
                hi = bisect.bisect_right(smz, m + tol)
                prof.append((c - m, float(sint[lo:hi].sum()) if hi > lo else 0.0))
            vals = np.array([v for _, v in prof])
            if vals.max() <= 0 or vals.max() < MIN_PEAK_RATIO * max(np.median(vals), 1e-9):
                continue
            norm = np.zeros(nbins)
            count = np.zeros(nbins)
            for d, v in prof:
                b = int(round((d + MAX_OFFSET) / STEP))
                if 0 <= b < nbins:
                    norm[b] += v / vals.max()
                    count[b] += 1
            row = np.where(count > 0, norm / np.maximum(count, 1), np.nan)
            groups['all'].append(row)
            groups[group_of(m)].append(row)

    def spectra():
        # Seek straight to the RT window through the file's byte index, rather than decoding
        # every spectrum before it; a ZT Scan mzML is about 20 GB.
        with mzml.PreIndexedMzML(path) as reader:
            start = reader.time[rt_lo]['index'] if rt_lo > 0 else 0
            # Back up to the MS1 that opens the cycle, so the first sweep is whole.
            while start > 0 and reader.get_by_index(start)['ms level'] != 1:
                start -= 1
            for i in range(start, len(reader)):
                yield reader.get_by_index(i)

    ms1 = None
    sweep = []
    if True:
        for s in spectra():
            t = float(s['scanList']['scan'][0]['scan start time'])
            if s['ms level'] == 1:
                flush(ms1, sweep)
                sweep = []
                ms1 = (s['m/z array'], s['intensity array']) if rt_lo <= t <= rt_hi else None
                if t > rt_hi:
                    break
            elif ms1 is not None:
                iw = s['precursorList']['precursor'][0]['isolationWindow']
                c = iw['isolation window target m/z']
                sweep.append((c, s['m/z array'], s['intensity array']))
    flush(ms1, sweep)

    offsets = -MAX_OFFSET + STEP * np.arange(nbins)
    with open(prefix + '.profile.tsv', 'w') as out:
        out.write('offset\t' + '\t'.join('%s (n=%d)' % (g, len(r)) for g, r in groups.items()) + '\n')
        med = {g: (np.nanmedian(np.array(r), axis=0) if r else np.full(nbins, np.nan)) for g, r in groups.items()}
        for b in range(nbins):
            out.write('%.2f\t' % offsets[b] + '\t'.join('%.4f' % med[g][b] for g in groups) + '\n')

    for g, r in groups.items():
        if not r:
            print('%-16s no probes' % g)
            continue
        p = np.nanmedian(np.array(r), axis=0)
        p = np.nan_to_num(p)
        peak = p.max()
        above = np.where(p >= peak / 2)[0]
        fwhm = (above[-1] - above[0]) * STEP if len(above) else float('nan')
        centroid = float((offsets * p).sum() / p.sum())
        apex = float(offsets[p.argmax()])
        # asymmetry: width left and right of the apex at half height
        left = apex - offsets[above[0]]
        right = offsets[above[-1]] - apex
        print('%-16s probes %6d  FWHM %.2f Th  apex %+.2f  centroid %+.2f  half-width left %.2f right %.2f'
              % (g, len(r), fwhm, apex, centroid, left, right))


if __name__ == '__main__':
    main()
