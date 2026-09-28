"""The ZT Scan TOF peak shape on its profile grid (uniform in sqrt(m/z)): for strong, isolated, single-maximum
profile peaks, the width in samples (sigma from the second moment) by m/z, and the average normalized shape
on the sample grid, aligned on each peak's centroid, as an empirical basis B for a joint demux/centroid solve.

Usage: python peak_shape.py <profile.mzML> [min counts]
"""
import sys

import numpy as np
from pyteomics import mzml

STEP = 9.786595e-05  # sqrt(m/z) per sample, from grid_check.py


def main():
    min_counts = float(sys.argv[2]) if len(sys.argv) > 2 else 5000
    sig, mzs, shapes = [], [], []
    grid = np.arange(-8, 8.01, 0.25)
    with mzml.MzML(sys.argv[1]) as reader:
        for s in reader:
            if s.get('ms level') != 2 or len(s['m/z array']) < 100:
                continue
            order = np.argsort(s['m/z array'])
            mz, inten = s['m/z array'][order], s['intensity array'][order]
            k = np.round((np.sqrt(mz) - np.sqrt(mz[0])) / STEP).astype(int)
            # Runs of consecutive sample indices.
            cut = np.where(np.diff(k) > 1)[0] + 1
            for seg_k, seg_i, seg_m in zip(np.split(k, cut), np.split(inten, cut), np.split(mz, cut)):
                total = seg_i.sum()
                if total < min_counts or len(seg_i) < 4:
                    continue
                top = np.argmax(seg_i)
                # Single maximum: rises to the top and falls after it (ion-counting noise allowed at 10%).
                rising = np.all(np.diff(seg_i[:top + 1]) >= -0.1 * seg_i[top])
                falling = np.all(np.diff(seg_i[top:]) <= 0.1 * seg_i[top])
                if not (rising and falling) or top == 0 or top == len(seg_i) - 1:
                    continue
                c = np.sum(seg_k * seg_i) / total
                sd = np.sqrt(np.sum((seg_k - c) ** 2 * seg_i) / total)
                sig.append(sd)
                mzs.append(np.sum(seg_m * seg_i) / total)
                shapes.append(np.interp(grid, seg_k - c, seg_i / seg_i.max(), left=0, right=0))
    sig, mzs = np.array(sig), np.array(mzs)
    print('%d strong isolated peaks (>= %.0f counts)' % (len(sig), min_counts))
    print('sigma in samples: median %.3f (p10 %.3f, p90 %.3f); FWHM ~ %.2f samples'
          % (np.median(sig), np.percentile(sig, 10), np.percentile(sig, 90), 2.355 * np.median(sig)))
    for lo, hi in ((150, 400), (400, 700), (700, 1000), (1000, 1600)):
        sel = (mzs >= lo) & (mzs < hi)
        if sel.sum() > 20:
            print('  m/z %4d-%4d: n %5d, sigma %.3f samples' % (lo, hi, sel.sum(), np.median(sig[sel])))
    mean = np.mean(shapes, axis=0)
    mean /= mean.max()
    gauss = np.exp(-0.5 * (grid / np.median(sig)) ** 2)
    print('average shape vs Gaussian at the median sigma (offset in samples: shape / gaussian):')
    print('  ' + '  '.join('%+.1f:%.2f/%.2f' % (g, v, w) for g, v, w in zip(grid[::4], mean[::4], gauss[::4])))


if __name__ == '__main__':
    main()
