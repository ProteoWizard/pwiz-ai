"""Where does a ZT Scan precursor's signal start and where does it disappear along the sweep?

For precursors DIA-NN identified (plain search, known m/z), take the apex sweep (and the sum of
apex +/- 1 sweeps), and for each of the top library fragments and the surviving precursor ion,
the intensity in each encoded bin within 14 bins of the precursor. From the bin of maximum
intensity, walk out to where the signal falls below a fraction of that maximum: the first and last
bins above it are where the signal starts and disappears. Reported relative to the precursor
m/z: onset (first bin center - m), end (last bin center - m), their midpoint (a position
estimate) and the span. The sweep runs up in m/z, so the onset is in spectra acquired first.

Usage: python Measure-ZtScanEdges.py <raw.mzML> <report.parquet> <library.parquet> [n] [frac]
"""
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from pyteomics import mzml

PPM = 20.0
TOP = 6
REACH = 14
MIN_IONS = 5.0  # at the profile maximum
ION = 100.0
ID = 'sample=1 period=1 cycle=%d experiment=%d'


def edges(p, frac):
    k = int(np.argmax(p))
    t = frac * p[k]
    a = k
    while a > 0 and p[a - 1] > t:
        a -= 1
    b = k
    while b < len(p) - 1 and p[b + 1] > t:
        b += 1
    return a, b, k


def summary(name, v):
    v = np.asarray(v)
    if len(v) == 0:
        return '%s: none' % name
    return '%s: median %+.2f, IQR %+.2f to %+.2f, sd %.2f' % (name, np.median(v), np.percentile(v, 25),
                                                              np.percentile(v, 75), np.std(v))


def main():
    raw, report, lib_path = sys.argv[1:4]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 300
    fracs = [float(sys.argv[5])] if len(sys.argv) > 5 else [0.05, 0.2]

    rep = pd.read_parquet(report, columns=['Precursor.Id', 'Precursor.Mz', 'Precursor.Charge', 'RT', 'Q.Value',
                                           'Protein.Ids', 'Precursor.Quantity'])
    rep = rep[(rep['Q.Value'] <= 0.01) & ~rep['Protein.Ids'].str.contains('_p_target', regex=False)
              & (rep['RT'] > 2.0) & (rep['RT'] < 10.0) & (rep['Precursor.Mz'] > 415) & (rep['Precursor.Mz'] < 875)]
    rep = rep.sample(n=min(n, len(rep)), random_state=5)
    lib = pq.read_table(lib_path, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                        filters=[('Precursor.Id', 'in', list(rep['Precursor.Id']))]).to_pandas()
    frags = {pid: g.nlargest(TOP, 'Relative.Intensity')['Product.Mz'].to_numpy() for pid, g in lib.groupby('Precursor.Id')}

    reader = mzml.PreIndexedMzML(raw)
    centers = np.array([reader.get_by_id(ID % (1, e))['precursorList']['precursor'][0]['isolationWindow']
                        ['isolation window target m/z'] for e in range(2, 431)])
    cache = {}

    def spectrum(c, b):
        key = (c, b)
        if key not in cache:
            s = reader.get_by_id(ID % (c, b + 2))
            it = s['intensity array']
            nz = it > 0
            cache[key] = (s['m/z array'][nz], it[nz] / ION)
        return cache[key]

    halves = [int(h) for h in sys.argv[6].split(',')] if len(sys.argv) > 6 else [1]
    if len(halves) > 1:
        sweep_comparison(rep, frags, centers, spectrum, halves, fracs[0])
        return
    results = {f: {'fragment': [], 'precursor': []} for f in fracs}
    per_prec_mid = {f: [] for f in fracs}
    for _, row in rep.iterrows():
        m = float(row['Precursor.Mz'])
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
                smz, sint = spectrum(c, b)
                for k, (_, fm) in enumerate(channels):
                    tol = fm * PPM * 1e-6
                    lo = np.searchsorted(smz, fm - tol)
                    hi = np.searchsorted(smz, fm + tol, side='right')
                    prof[k, bi] += sint[lo:hi].sum()
        cb = centers[bins]
        for f in fracs:
            mids = []
            for k, (kind, _) in enumerate(channels):
                p = prof[k]
                if p.max() < MIN_IONS:
                    continue
                a, b, top = edges(p, f)
                if a == 0 or b == len(p) - 1:
                    continue  # the signal runs past the bins examined: another source in the channel
                rec = (cb[a] - m, cb[b] - m, 0.5 * (cb[a] + cb[b]) - m, cb[b] - cb[a], p.max(), cb[top] - m)
                results[f][kind].append(rec)
                if kind == 'fragment':
                    mids.append(rec[2])
            if len(mids) >= 3:
                per_prec_mid[f].append(np.median(mids))

    print('%d precursors; profiles summed over the apex sweep +/- 1; offsets in Th from the precursor m/z '
          '(bins are 1.18 Th apart)' % len(rep))
    for f in fracs:
        print('\nthreshold %.0f%% of the profile maximum' % (100 * f))
        for kind in ('fragment', 'precursor'):
            r = np.array(results[f][kind])
            if len(r) == 0:
                continue
            print('  %s channels: %d' % (kind, len(r)))
            print('    ' + summary('onset (first bin)', r[:, 0]))
            print('    ' + summary('end (last bin)   ', r[:, 1]))
            print('    ' + summary('span             ', r[:, 3]))
            print('    ' + summary('midpoint - m     ', r[:, 2]))
            print('    ' + summary('peak bin - m     ', r[:, 5]))
            ions = r[:, 4]
            q = np.quantile(ions, [1 / 3, 2 / 3])
            for label, mask in (('low', ions <= q[0]), ('mid', (ions > q[0]) & (ions <= q[1])), ('high', ions > q[1])):
                print('    %-4s (%5.0f-%6.0f ions at max): %s' % (label, ions[mask].min(), ions[mask].max(),
                                                                  summary('midpoint - m', r[mask, 2])))
        pm = np.array(per_prec_mid[f])
        print('  per precursor, median midpoint over its fragments (%d precursors): %s; within 0.59 Th: %.0f%%'
              % (len(pm), summary('', pm)[2:], 100 * (np.abs(pm) <= 0.59).mean()))


def sweep_comparison(rep, frags, centers, spectrum, halves, frac):
    """Per fragment channel, the start/end midpoint's error against the precursor m/z from the apex
    sweep alone and from the apex +/- h sweeps summed: share within half a bin (0.59 Th, the right
    bin) and within 1.77 Th (the 3 bins centered on the right bin), by ions at the profile maximum
    in the single apex sweep."""
    recs = []
    for _, row in rep.iterrows():
        m = float(row['Precursor.Mz'])
        mzs = frags.get(row['Precursor.Id'])
        if mzs is None:
            continue
        j0 = int(np.argmin(np.abs(centers - m)))
        bins = np.arange(max(0, j0 - REACH), min(len(centers), j0 + REACH + 1))
        apex = int(round(row['RT'] * 60 / 0.971)) + 1
        H = max(halves)
        per_cycle = np.zeros((2 * H + 1, len(mzs), len(bins)))
        for ci, c in enumerate(range(apex - H, apex + H + 1)):
            for bi, b in enumerate(bins):
                smz, sint = spectrum(c, b)
                for k, fm in enumerate(mzs):
                    tol = fm * PPM * 1e-6
                    lo = np.searchsorted(smz, fm - tol)
                    hi = np.searchsorted(smz, fm + tol, side='right')
                    per_cycle[ci, k, bi] = sint[lo:hi].sum()
        cb = centers[bins]
        for k in range(len(mzs)):
            single = per_cycle[H, k]
            if single.max() < MIN_IONS:
                continue
            rec = {'ions': single.max()}
            for h in halves:
                p = per_cycle[H - h:H + h + 1, k].sum(axis=0)
                a, b, _ = edges(p, frac)
                rec[h] = np.nan if (a == 0 or b == len(p) - 1) else 0.5 * (cb[a] + cb[b]) - m
            recs.append(rec)
    ions = np.array([r['ions'] for r in recs])
    q = np.quantile(ions, [1 / 3, 2 / 3])
    print('%d fragment channels (>= %.0f ions at the apex maximum); threshold %.0f%% of the maximum'
          % (len(recs), MIN_IONS, 100 * frac))
    print('%-28s ' % 'group' + '  '.join('%-24s' % ('apex +/- %d sweeps' % h) for h in halves))
    groups = [('all', np.ones(len(recs), bool)), ('low (%.0f-%.0f ions)' % (ions.min(), q[0]), ions <= q[0]),
              ('mid (%.0f-%.0f ions)' % (q[0], q[1]), (ions > q[0]) & (ions <= q[1])),
              ('high (%.0f-%.0f ions)' % (q[1], ions.max()), ions > q[1])]
    for label, mask in groups:
        cells = []
        for h in halves:
            e = np.array([r[h] for r in recs])[mask]
            e = e[np.isfinite(e)]
            cells.append('%3.0f%% / %3.0f%% (n %d)' % (100 * (np.abs(e) <= 0.59).mean(), 100 * (np.abs(e) <= 1.77).mean(),
                                                     len(e)))
        print('%-28s ' % label + '  '.join('%-24s' % c for c in cells))
    print('cells: share of midpoints within 0.59 Th (right bin) / within 1.77 Th (3 bins centered on it)')


if __name__ == '__main__':
    main()
