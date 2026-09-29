"""Calibrate the ZT Scan transmission shape from identified precursors (spec 2.4), by m/z range.

For precursors DIA-NN identified (known m/z), the intensity of each top library fragment and of the
surviving precursor ion in the encoded bins within 14 bins of the precursor, summed over the apex
sweep +/- 1. Each channel's profile samples the transmission at offsets d = bin center - precursor
m/z; precursors fall at every phase relative to the bin grid, so pooling many channels samples the
shape finely. Channels are kept when their profile starts and ends inside the bins examined (no
other source in the channel at the edges) and they reach MIN_IONS at the maximum. Each is
normalized to unit area, the pooled samples are averaged on a 0.25 Th grid, and the result is
scaled to a maximum of 1.

Reported per m/z range: where the shape crosses 10%, 50% and 90% of its maximum on the rising side
(negative offsets: bins acquired before the window reaches the precursor, the sweep runs up in m/z)
and on the falling side, the rise and fall widths (10-90%), the position of the maximum and the
centroid. Writes <out>.tsv with the shape per range.

Usage: python Measure-ZtScanTransmission.py <raw.mzML> <report.parquet> <library.parquet> <out> [n]
"""
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from pyteomics import mzml

PPM = 20.0
TOP = 6
REACH = 14
MIN_IONS = 20.0
ION = 100.0
STEP = 0.25
GRID = np.arange(-14.0, 14.0001, STEP)
ID = 'sample=1 period=1 cycle=%d experiment=%d'
RANGES = [(415, 530), (530, 645), (645, 760), (760, 875)]


def crossings(shape, level):
    """Offsets where the shape first rises through level (from the left) and last falls through it."""
    k = int(np.argmax(shape))
    left = np.nan
    for i in range(k, 0, -1):
        if shape[i - 1] < level <= shape[i]:
            left = GRID[i - 1] + (level - shape[i - 1]) / (shape[i] - shape[i - 1]) * STEP
            break
    right = np.nan
    for i in range(k, len(shape) - 1):
        if shape[i] >= level > shape[i + 1]:
            right = GRID[i] + (shape[i] - level) / (shape[i] - shape[i + 1]) * STEP
            break
    return left, right


def main():
    raw, report, lib_path, out = sys.argv[1:5]
    n = int(sys.argv[5]) if len(sys.argv) > 5 else 1500
    rep = pd.read_parquet(report, columns=['Precursor.Id', 'Precursor.Mz', 'Precursor.Charge', 'RT', 'Q.Value',
                                           'Protein.Ids'])
    rep = rep[(rep['Q.Value'] <= 0.01) & ~rep['Protein.Ids'].str.contains('_p_target', regex=False)
              & (rep['RT'] > 2.0) & (rep['RT'] < 10.0) & (rep['Precursor.Mz'] > RANGES[0][0])
              & (rep['Precursor.Mz'] < RANGES[-1][1])]
    rep = rep.sample(n=min(n, len(rep)), random_state=11)
    lib = pq.read_table(lib_path, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                        filters=[('Precursor.Id', 'in', list(rep['Precursor.Id']))]).to_pandas()
    frags = {pid: g.nlargest(TOP, 'Relative.Intensity')['Product.Mz'].to_numpy() for pid, g in lib.groupby('Precursor.Id')}
    reader = mzml.PreIndexedMzML(raw)
    centers = np.array([reader.get_by_id(ID % (1, e))['precursorList']['precursor'][0]['isolationWindow']
                        ['isolation window target m/z'] for e in range(2, 431)])

    samples = {(r, kind): ([], []) for r in range(len(RANGES)) for kind in ('fragment', 'precursor')}
    kept = {key: 0 for key in samples}
    for _, row in rep.iterrows():
        m = float(row['Precursor.Mz'])
        r = next(i for i, (lo, hi) in enumerate(RANGES) if lo <= m < hi)
        mzs = frags.get(row['Precursor.Id'])
        if mzs is None:
            continue
        j0 = int(np.argmin(np.abs(centers - m)))
        bins = np.arange(max(0, j0 - REACH), min(len(centers), j0 + REACH + 1))
        apex = int(round(row['RT'] * 60 / 0.971)) + 1
        channels = [('fragment', fm) for fm in mzs] + [('precursor', m)]
        prof = np.zeros((len(channels), len(bins)))
        for c in (apex - 1, apex, apex + 1):
            for bi, b in enumerate(bins):
                s = reader.get_by_id(ID % (c, b + 2))
                smz, sint = s['m/z array'], s['intensity array'] / ION
                for k, (_, fm) in enumerate(channels):
                    tol = fm * PPM * 1e-6
                    lo = np.searchsorted(smz, fm - tol)
                    hi = np.searchsorted(smz, fm + tol, side='right')
                    prof[k, bi] = prof[k, bi] + sint[lo:hi].sum()
        d = centers[bins] - m
        for k, (kind, _) in enumerate(channels):
            p = prof[k]
            if p.max() < MIN_IONS or p[0] > 0.02 * p.max() or p[-1] > 0.02 * p.max():
                continue
            samples[(r, kind)][0].append(d)
            samples[(r, kind)][1].append(p / p.sum())
            kept[(r, kind)] += 1

    table = {'offset': GRID}
    print('%d precursors; profiles summed over the apex sweep +/- 1; offsets = bin center - precursor m/z (Th)'
          % len(rep))
    print('%-22s %6s | %-15s %-15s %-15s | %5s %5s | %6s %8s' % ('range, channel', 'n', '10% rise/fall', '50% rise/fall',
                                                                '90% rise/fall', 'rise', 'fall', 'max at', 'centroid'))
    for r, (lo, hi) in enumerate(RANGES):
        for kind in ('fragment', 'precursor'):
            ds, ps = samples[(r, kind)]
            if len(ds) < 20:
                continue
            dd = np.concatenate(ds)
            pp = np.concatenate(ps)
            idx = np.round((dd - GRID[0]) / STEP).astype(int)
            ok = (idx >= 0) & (idx < len(GRID))
            sums = np.bincount(idx[ok], weights=pp[ok], minlength=len(GRID))
            cnt = np.bincount(idx[ok], minlength=len(GRID))
            shape = np.where(cnt > 0, sums / np.maximum(cnt, 1), 0.0)
            # Smooth over +/- 0.5 Th to average the bin-grid phase, then scale to a maximum of 1.
            kern = np.ones(5) / 5
            shape = np.convolve(shape, kern, mode='same')
            shape /= shape.max()
            table['%d-%d %s' % (lo, hi, kind)] = shape
            l10, r10 = crossings(shape, 0.1)
            l50, r50 = crossings(shape, 0.5)
            l90, r90 = crossings(shape, 0.9)
            centroid = float((GRID * shape).sum() / shape.sum())
            print('%-22s %6d | %+5.1f / %+5.1f   %+5.1f / %+5.1f   %+5.1f / %+5.1f   | %5.1f %5.1f | %+6.2f %+8.2f'
                  % ('%d-%d %s' % (lo, hi, kind), kept[(r, kind)], l10, r10, l50, r50, l90, r90, l90 - l10, r10 - r90,
                     GRID[int(np.argmax(shape))], centroid))
    pd.DataFrame(table).to_csv(out + '.tsv', sep='\t', index=False, float_format='%.4f')
    print('wrote %s.tsv' % out)


if __name__ == '__main__':
    main()
