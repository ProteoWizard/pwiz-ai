"""
Scores demultiplexing against truth on remultiplexed narrow-window data (the Stellar truth benchmark of
pwiz_tools/Osprey/docs/24-profile-centroiding.md and TODO-20261021_osprey_stellar_demux.md).

Usage: python eval_remux.py <truth.mzML> <remux.mzML> <output.mzML> [<output.mzML> ...]

truth: the narrow-window run (each spectrum = one bin at one cycle), centroided like the outputs.
remux: the synthetic staggered run from Osprey.DemuxTool --remultiplex K (ids carry the first member's scan
       and ' remux=g').
outputs: demultiplexed mzMLs (ids = remux id + ' demux=p', isolation window = the bin).

Every spectrum becomes ions (intensity x fill time / 1000) on a 0.05 Th grid, each point blurred by a Gaussian
of 0.3 Th so the score does not depend on exactly where a centroid lands. Per (bin, cycle) with at least 50 true
ions: cosine to truth, and output/truth ion ratio; printed as median, ion-weighted median and 10th percentile.
Baseline 'no-demux': the staggered window's own spectrum standing in for each of its bins.
"""
import re
import sys
import numpy as np
from pyteomics import mzml

NOMINAL = 1.000495
SCAN = re.compile(r'scan=(\d+)')


GRID = np.arange(150, 1250, 0.05)
SIGMA = 0.3


def nominal_vector(mz, y, fill):
    """Ions on a 0.05 Th grid, each point blurred by a Gaussian of SIGMA Th: robust to where a centroid lands."""
    v = np.zeros(len(GRID))
    a = y * fill / 1000.0
    keep = a > 0
    idx = np.searchsorted(GRID, mz[keep])
    reach = int(4 * SIGMA / 0.05)
    kern = np.exp(-0.5 * ((np.arange(-reach, reach + 1) * 0.05) / SIGMA) ** 2)
    for i, w in zip(idx, a[keep]):
        lo, hi = i - reach, i + reach + 1
        if lo < 0 or hi > len(GRID):
            continue
        v[lo:hi] += w * kern
    return v


def read(path):
    out = []
    with mzml.MzML(path, decode_binary=True) as f:
        for s in f:
            lvl = s.get('ms level')
            scan = int(SCAN.search(s['id']).group(1))
            if lvl == 1:
                out.append((1, scan, None, None, None))
                continue
            w = s['precursorList']['precursor'][0]['isolationWindow']
            center = float(w['isolation window target m/z'])
            fill = float(s['scanList']['scan'][0].get('ion injection time', 1000.0))
            out.append((2, scan, round(center, 2), nominal_vector(s['m/z array'], s['intensity array'], fill), s['id']))
    return out


truth_raw = read(sys.argv[1])
# Truth cycles: MS1 delimits them; each truth MS2 is (cycle, bin center).
cycle_of_scan, truth = {}, {}
cycle = -1
for lvl, scan, center, vec, sid in truth_raw:
    if lvl == 1:
        cycle += 1
        continue
    cycle_of_scan[scan] = cycle
    truth[(cycle, center)] = vec
bins = sorted({c for (_, c) in truth})
half = np.median(np.diff(bins)) / 2


def bin_of(center):
    j = int(np.argmin([abs(b - center) for b in bins]))
    return bins[j]


def score(pairs, label):
    cos, ratio, w = [], [], []
    for key, vec in pairs.items():
        t = truth.get(key)
        if t is None or t.sum() < 50:
            continue
        n = np.linalg.norm(vec) * np.linalg.norm(t)
        cos.append(vec @ t / n if n > 0 else 0.0)
        ratio.append(vec.sum() / t.sum())
        w.append(t.sum())
    cos, ratio, w = np.array(cos), np.array(ratio), np.array(w)
    order = np.argsort(cos)
    cw = np.cumsum(w[order]) / w.sum()
    wmed = cos[order][np.searchsorted(cw, 0.5)]
    print('%-14s n %5d  cosine median %.3f  ion-weighted median %.3f  p10 %.3f  | ions out/truth median %.3f'
          % (label, len(cos), np.median(cos), wmed, np.percentile(cos, 10), np.median(ratio)))


# Baseline: each output's parent staggered spectrum (exact window membership) standing in for its bin.
remux = read(sys.argv[2])
nodemux = {}
for path in sys.argv[3:]:
    pairs, parents = {}, {}
    for lvl, scan, center, vec, sid in read(path):
        if lvl == 1:
            continue
        key = (cycle_of_scan[scan], bin_of(center))
        pairs[key] = vec
        parents[key] = sid.split(' demux=')[0]
    if not nodemux:
        remux_by_id = {sid: vec for lvl, scan, center, vec, sid in remux if lvl == 2}
        nodemux = {key: remux_by_id[p] for key, p in parents.items() if p in remux_by_id}
        score(nodemux, 'no-demux')
    score(pairs, path.replace('\\', '/').split('/')[-1].replace('.mzML', ''))
