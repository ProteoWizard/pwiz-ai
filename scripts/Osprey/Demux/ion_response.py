"""The single-ion response of a ZT Scan run: the histogram of the smallest MS2 centroid intensities in an
acquired (vendor-centroided) mzML, on a log scale, over spectra inside the gradient. A TOF detector's
single-ion events show as a mode; counts per ion is where it sits.

Usage: python ion_response.py <acquired.mzML> [n spectra] [skip]
"""
import sys

import numpy as np
from pyteomics import mzml


def main():
    path = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
    skip = int(sys.argv[3]) if len(sys.argv) > 3 else 120000
    values = []
    taken = 0
    with mzml.MzML(path, use_index=True) as reader:
        for i in range(skip, skip + 5 * n):
            s = reader[i]
            if s.get('ms level') != 2:
                continue
            values.append(s['intensity array'])
            taken += 1
            if taken >= n:
                break
    v = np.concatenate(values)
    v = v[v > 0]
    print('%d spectra, %d peaks; min %.3g, p1 %.3g, p5 %.3g, p25 %.3g, median %.3g'
          % (taken, len(v), v.min(), *np.percentile(v, [1, 5, 25, 50])))
    edges = np.logspace(np.log10(max(v.min(), 1e-3)), np.log10(np.percentile(v, 90)), 41)
    counts, _ = np.histogram(v, edges)
    top = counts.max()
    for lo, hi, c in zip(edges[:-1], edges[1:], counts):
        print('%9.2f - %9.2f %8d %s' % (lo, hi, c, '#' * int(60 * c / top)))
    # The most common exact values: centroids of single events often repeat.
    uniq, cnt = np.unique(np.round(v, 2), return_counts=True)
    order = np.argsort(-cnt)[:12]
    print('most common intensities:', ', '.join('%.2f (%d)' % (uniq[k], cnt[k]) for k in order))


if __name__ == '__main__':
    main()
