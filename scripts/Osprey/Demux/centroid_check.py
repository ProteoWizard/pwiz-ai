"""What SCIEX vendor centroiding keeps of a ZT Scan profile spectrum: per MS2 spectrum present in both
files, the total intensity of each, the share of profile intensity within +/- PPM of any vendor centroid,
and each centroid's intensity against the profile intensity summed within +/- PPM of it (1 = the centroid
is the peak's area; well under 1 = its height or a partial sum).

Usage: python centroid_check.py <profile.mzML> <vendor.mzML> [ppm]
"""
import sys

import numpy as np
from pyteomics import mzml


def spectra(path):
    out = {}
    with mzml.MzML(path) as reader:
        for s in reader:
            if s.get('ms level') == 2 and len(s['m/z array']):
                out[s['id']] = (s['m/z array'], s['intensity array'])
    return out


def main():
    ppm = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    profile = spectra(sys.argv[1])
    vendor = spectra(sys.argv[2])
    ids = sorted(set(profile) & set(vendor))
    tic_ratio, near_share, peak_ratio, peaks_v, points_p = [], [], [], [], []
    for sid in ids:
        pmz, pint = profile[sid]
        vmz, vint = vendor[sid]
        order = np.argsort(pmz)
        pmz, pint = pmz[order], pint[order]
        tic_ratio.append(vint.sum() / max(pint.sum(), 1e-30))
        lo = np.searchsorted(pmz, vmz * (1 - ppm * 1e-6))
        hi = np.searchsorted(pmz, vmz * (1 + ppm * 1e-6))
        cum = np.concatenate(([0.0], np.cumsum(pint)))
        area = cum[hi] - cum[lo]
        covered = np.zeros(len(pmz), bool)
        for a, b in zip(lo, hi):
            covered[a:b] = True
        near_share.append(pint[covered].sum() / max(pint.sum(), 1e-30))
        ok = area > 0
        peak_ratio.extend((vint[ok] / area[ok]).tolist())
        peaks_v.append(len(vmz))
        points_p.append(len(pmz))
    peak_ratio = np.array(peak_ratio)
    print('%d MS2 spectra in both; vendor peaks/spectrum %.0f, profile points/spectrum %.0f'
          % (len(ids), np.mean(peaks_v), np.mean(points_p)))
    print('vendor TIC / profile TIC: median %.3f (p10 %.3f, p90 %.3f)' % tuple(np.percentile(tic_ratio, [50, 10, 90])))
    print('profile intensity within %.0f ppm of a vendor centroid: median %.3f' % (ppm, np.median(near_share)))
    print('centroid / profile sum within %.0f ppm: median %.3f (p10 %.3f, p90 %.3f)'
          % ((ppm,) + tuple(np.percentile(peak_ratio, [50, 10, 90]))))


if __name__ == '__main__':
    main()
