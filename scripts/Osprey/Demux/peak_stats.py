"""Peak statistics of demultiplexed slice mzML files over the same spectra: peaks per spectrum, total
intensity, and the share of peaks and intensity under 1 and 5 ions (100 counts per ion).

Usage: python peak_stats.py <n spectra> <label>=<mzML> [...]
"""
import sys

import numpy as np
from pyteomics import mzml


def stats(path, n):
    counts, total, peaks_small1, peaks_small5, int_small1, int_small5 = [], 0.0, 0, 0, 0.0, 0.0
    with mzml.MzML(path, use_index=True) as reader:
        # Skip the first sweeps so the sample is inside the slice's elution, then take n MS2 spectra.
        taken = 0
        for i, spectrum in enumerate(reader):
            if spectrum.get('ms level') != 2 or i < 8000:
                continue
            ions = spectrum['intensity array'] / 100.0
            counts.append(len(ions))
            total += ions.sum()
            peaks_small1 += int((ions < 1).sum())
            peaks_small5 += int((ions < 5).sum())
            int_small1 += float(ions[ions < 1].sum())
            int_small5 += float(ions[ions < 5].sum())
            taken += 1
            if taken >= n:
                break
    peaks = sum(counts)
    return len(counts), np.mean(counts), total, peaks_small1 / peaks, peaks_small5 / peaks, int_small1 / total, \
        int_small5 / total


def main():
    n = int(sys.argv[1])
    print('%-14s %6s %9s %12s %8s %8s %8s %8s' % ('arm', 'spectra', 'peaks/sp', 'ions', 'pk<1', 'pk<5',
                                                    'int<1', 'int<5'))
    for arg in sys.argv[2:]:
        label, path = arg.split('=', 1)
        s = stats(path, n)
        print('%-14s %6d %9.1f %12.4g %7.1f%% %7.1f%% %7.2f%% %7.2f%%' % (label, s[0], s[1], s[2], 100 * s[3],
                                                                          100 * s[4], 100 * s[5], 100 * s[6]))


if __name__ == '__main__':
    main()
