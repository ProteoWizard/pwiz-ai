"""Parity between two demultiplexed mzML files of the same slice and layout (the Python prototype and
the C# Osprey.DemuxTool): spectra paired by sweep and isolation window, then per pair the cosine of
the peak intensities (peaks matched within 10 ppm), the ratio of total intensity, and the share of
intensity in peaks only one side has.

Usage: python Compare-DemuxParity.py <a.mzML> <b.mzML>
"""
import re
import sys

import numpy as np
from pyteomics import mzml

PPM = 10.0


def spectra(path):
    out = {}
    for s in mzml.MzML(path):
        if s['ms level'] != 2:
            continue
        found = re.search(r'cycle=(\d+)', s['id'])
        if found:
            # SCIEX ids name the sweep; a tiled window is identified by its target.
            target = s['precursorList']['precursor'][0]['isolationWindow']['isolation window target m/z']
            key = (int(found.group(1)), round(target, 1))
        else:
            # Thermo: msconvert writes "originalScan=N demux=k scan=M", Osprey.DemuxTool "scan=N demux=k".
            scan = re.search(r'originalScan=(\d+)', s['id']) or re.search(r'scan=(\d+)', s['id'])
            demux = re.search(r'demux=(\d+)', s['id'])
            key = (int(scan.group(1)), int(demux.group(1)) if demux else -1)
        out[key] = (s['m/z array'], s['intensity array'])
    return out


def match(ma, ia, mb, ib):
    """Paired intensities of peaks within PPM, nearest first; unmatched peaks pair with 0."""
    j = np.searchsorted(mb, ma)
    pa, pb, used = [], [], np.zeros(len(mb), bool)
    for i, m in enumerate(ma):
        best, bd = -1, m * PPM * 1e-6
        for k in (j[i] - 1, j[i]):
            if 0 <= k < len(mb) and not used[k] and abs(mb[k] - m) <= bd:
                best, bd = k, abs(mb[k] - m)
        if best >= 0:
            used[best] = True
            pa.append(ia[i])
            pb.append(ib[best])
        else:
            pa.append(ia[i])
            pb.append(0.0)
    for k in np.nonzero(~used)[0]:
        pa.append(0.0)
        pb.append(ib[k])
    return np.array(pa), np.array(pb)


def main():
    a, b = spectra(sys.argv[1]), spectra(sys.argv[2])
    keys = sorted(set(a) & set(b))
    print('spectra: %d in a, %d in b, %d paired' % (len(a), len(b), len(keys)))
    cos, ratio, only = [], [], []
    for key in keys:
        pa, pb = match(*a[key], *b[key])
        if pa.sum() == 0 and pb.sum() == 0:
            continue
        na, nb = np.linalg.norm(pa), np.linalg.norm(pb)
        cos.append(pa @ pb / (na * nb) if na > 0 and nb > 0 else 0.0)
        ratio.append(pb.sum() / max(pa.sum(), 1e-9))
        only.append((pa[pb == 0].sum() + pb[pa == 0].sum()) / (pa.sum() + pb.sum()))
    cos, ratio, only = np.array(cos), np.array(ratio), np.array(only)
    print('cosine: median %.4f, p05 %.4f; >= 0.99: %.1f%%' % (np.median(cos), np.percentile(cos, 5),
                                                             100 * (cos >= 0.99).mean()))
    print('total intensity b / a: median %.4f, p05 %.4f, p95 %.4f' % (np.median(ratio), np.percentile(ratio, 5),
                                                                     np.percentile(ratio, 95)))
    print('intensity in unmatched peaks: median %.2f%%' % (100 * np.median(only)))


if __name__ == '__main__':
    main()
