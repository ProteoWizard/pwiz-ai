"""The profile peaks of ZT Scan MS2 spectra and which of them vendor centroiding keeps: contiguous runs of
profile points (split where the m/z gap exceeds 3x the local point spacing) are peaks; each peak's summed
intensity, and whether a vendor centroid lies within PPM of its intensity-weighted m/z. Prints the
distribution of peak sums for kept and dropped peaks, and the share of the profile's intensity each holds.

Usage: python profile_events.py <profile.mzML> <vendor.mzML> [ppm]
"""
import sys

import numpy as np
from pyteomics import mzml


def spectra(path):
    out = {}
    with mzml.MzML(path) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']):
                order = np.argsort(s['m/z array'])
                out[s['id']] = (s['m/z array'][order], s['intensity array'][order])
    return out


def peaks_of(mz, inten):
    gaps = np.diff(mz)
    spacing = np.median(gaps) if len(gaps) else 0
    # A gap well above the local spacing (which grows with m/z on a TOF) ends a peak.
    rel = gaps / mz[:-1]
    cut = np.where(rel > 3 * np.median(rel))[0] + 1
    starts = np.concatenate(([0], cut))
    ends = np.concatenate((cut, [len(mz)]))
    sums = np.add.reduceat(inten, starts)
    centers = np.add.reduceat(inten * mz, starts) / sums
    widths = ends - starts
    heights = np.maximum.reduceat(inten, starts)
    return centers, sums, widths, heights


def main():
    ppm = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    profile = spectra(sys.argv[1])
    vendor = spectra(sys.argv[2])
    kept_sums, dropped_sums, kept_w, dropped_w, kept_h, dropped_h, ratio = [], [], [], [], [], [], []
    for sid in sorted(set(profile) & set(vendor)):
        centers, sums, widths, heights = peaks_of(*profile[sid])
        vmz, vint = vendor[sid]
        pos = np.searchsorted(vmz, centers)
        best = np.full(len(centers), np.inf)
        best_int = np.zeros(len(centers))
        for off in (-1, 0):
            idx = np.clip(pos + off, 0, len(vmz) - 1)
            d = np.abs(vmz[idx] - centers) / centers * 1e6
            better = d < best
            best[better] = d[better]
            best_int[better] = vint[idx][better]
        kept = best <= ppm
        kept_sums.append(sums[kept])
        dropped_sums.append(sums[~kept])
        kept_w.append(widths[kept])
        dropped_w.append(widths[~kept])
        kept_h.append(heights[kept])
        dropped_h.append(heights[~kept])
        ratio.append(best_int[kept] / sums[kept])
    ks, ds = np.concatenate(kept_sums), np.concatenate(dropped_sums)
    total = ks.sum() + ds.sum()
    print('profile peaks: %d kept (%.1f%% of intensity), %d dropped (%.1f%% of intensity)'
          % (len(ks), 100 * ks.sum() / total, len(ds), 100 * ds.sum() / total))
    print('peak width (points): kept median %d, dropped median %d' % (np.median(np.concatenate(kept_w)),
                                                                      np.median(np.concatenate(dropped_w))))
    print('peak height: kept median %.1f, dropped median %.1f' % (np.median(np.concatenate(kept_h)),
                                                                   np.median(np.concatenate(dropped_h))))
    print('vendor centroid / profile peak sum (kept): median %.3f' % np.median(np.concatenate(ratio)))
    edges = np.logspace(np.log10(max(min(ks.min(), ds.min()), 1e-3)), np.log10(np.percentile(ks, 99)), 31)
    hk, _ = np.histogram(ks, edges)
    hd, _ = np.histogram(ds, edges)
    top = max(hk.max(), hd.max())
    print('%21s %8s %8s' % ('profile peak sum', 'kept', 'dropped'))
    for lo, hi, a, b in zip(edges[:-1], edges[1:], hk, hd):
        print('%9.1f - %9.1f %8d %8d  %-30s|%s' % (lo, hi, a, b, '#' * int(30 * a / top), '#' * int(30 * b / top)))


if __name__ == '__main__':
    main()
