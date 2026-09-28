"""How precisely does a fragment's quadrupole (Q1) profile give its precursor's m/z, with no candidate?

For precursors DIA-NN identified on A1 in the slice (the true m/z known), each top library fragment's
ions are extracted from the encoded bins around the precursor and summed over the sweeps around DIA-NN's
apex. That profile is fitted, blind, with the measured kernel at every position of a 0.1 Th grid over
+/- 24 Th (NNLS, then a Poisson-weighted refit), so other sources in the channel get their own shapes.
The solution's clusters (grid points with a solved intensity, gaps of more than 0.3 Th between clusters)
are sources; the one nearest the precursor, within 3 Th, gives the fragment's position (its intensity-
weighted mean). Reported: the error against the precursor m/z by the fragment's ions, and for the
precursor, its fragments' positions combined by their ions.

Usage: python position_test.py [--workers 6] [--apex 2]
"""
import argparse
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from scipy.optimize import nnls

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anchored_prototype as ap  # noqa: E402
from ztscan_real import FIRST, STEP  # noqa: E402

GRID = 0.1
SPAN = 24.0
GAP = 0.3
NEAR = 3.0
APEX = 2


def init(apex, shift, kernel, column):
    ap.init_worker(None)
    ap._state['apex'] = apex
    if kernel:
        rows = np.genfromtxt(kernel, delimiter='\t', skip_header=1)
        off, val = rows[:, 0], np.nan_to_num(rows[:, column])
        half = np.linspace(-STEP / 2, STEP / 2, 41)
        ap._state['off'], ap._state['val'] = off, val / np.interp(half, off, val).mean()
    # A kernel shifted by `shift` Th: k'(d) = k(d + shift).
    ap._state['off'] = ap._state['off'] - shift


def fit_positions(task):
    pid, mz, ci0, fmz, fint = task
    key, csum, rt = ap._state['key'], ap._state['csum'], ap._state['rt']
    rr = ap._state['rows_rel']
    off, val = ap._state['off'], ap._state['val']
    nb = ap.BINS[1] - ap.BINS[0] + 1
    pbin, _ = ap.bin_of(mz)
    rows_mz = ap.TARGET0 + (pbin + rr) * ap.TARGET_STEP
    sweeps = np.arange(max(0, ci0 - ap._state['apex']), min(len(rt), ci0 + ap._state['apex'] + 1))
    spec = (sweeps[None, :] * nb + (pbin + rr - ap.BINS[0])[:, None]).astype(np.float64)
    grid = mz + np.arange(-SPAN, SPAN + GRID / 2, GRID)
    k = np.interp(rows_mz[:, None] - grid[None, :], off, val, left=0.0, right=0.0)
    tol = ap.TOL_PPM * 1e-6
    out = []
    for f in range(len(fmz)):
        lo = np.searchsorted(key, (spec * 1e4 + fmz[f] * (1 - tol)).ravel())
        hi = np.searchsorted(key, (spec * 1e4 + fmz[f] * (1 + tol)).ravel(), side='right')
        y = (csum[hi] - csum[lo]).reshape(spec.shape).sum(axis=1)
        ions = float(y[np.abs(rr) <= ap.REACH].sum())
        if ions <= 0:
            out.append((pid, f, ions, np.nan, 0.0))
            continue
        x = nnls(k, y, maxiter=20 * k.shape[1])[0]
        sw = 1.0 / np.sqrt(np.maximum(k @ x, ap.FLOOR))
        x = nnls(k * sw[:, None], y * sw, maxiter=20 * k.shape[1])[0]
        nz = np.where(x > 1e-6)[0]
        best, best_err, best_amount = None, np.inf, 0.0
        if len(nz):
            breaks = np.where(np.diff(grid[nz]) > GAP + 1e-9)[0] + 1
            for cluster in np.split(nz, breaks):
                amount = x[cluster].sum()
                pos = float((grid[cluster] * x[cluster]).sum() / amount)
                if abs(pos - mz) < abs(best_err) and abs(pos - mz) <= NEAR:
                    best, best_err, best_amount = pos, pos - mz, amount
        out.append((pid, f, ions, best_err if best is not None else np.nan, float(best_amount)))
    return out


def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('--workers', type=int, default=6)
    argp.add_argument('--apex', type=int, default=APEX)
    argp.add_argument('--shift', type=float, default=0.0)
    argp.add_argument('--kernel', default='')
    argp.add_argument('--column', type=int, default=1)
    args = argp.parse_args()
    key, csum, rt = ap.load_slice(args.workers)
    rep = pd.read_parquet(ap.RT_REPORT, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Q.Value'])
    rep = rep[(rep['Q.Value'] <= 0.01) & rep['Precursor.Mz'].between(*ap.MZ_RANGE) & rep['RT'].between(*ap.RT_RANGE)]
    rep = rep.drop_duplicates('Precursor.Id')
    frag = pq.read_table(ap.LIB, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                         filters=[('Precursor.Id', 'in', list(rep['Precursor.Id']))]).to_pandas()
    frag = frag.sort_values(['Precursor.Id', 'Relative.Intensity'], ascending=[True, False], kind='stable')
    frag = frag.groupby('Precursor.Id', sort=True).head(ap.TOP)
    rep = rep.set_index('Precursor.Id')
    tasks = []
    for pid, g in frag.groupby('Precursor.Id', sort=True):
        r = rep.loc[pid]
        ci0 = int(np.argmin(np.abs(np.asarray(rt) - r['RT'])))
        tasks.append((pid, float(r['Precursor.Mz']), ci0, g['Product.Mz'].values.astype(np.float64),
                      g['Relative.Intensity'].values.astype(np.float64)))
    t0 = time.time()
    rows = []
    with ProcessPoolExecutor(max_workers=args.workers, initializer=init, initargs=(args.apex, args.shift, args.kernel, args.column)) as ex:
        for part in ex.map(fit_positions, tasks, chunksize=16):
            rows.extend(part)
    df = pd.DataFrame(rows, columns=['id', 'fragment', 'ions', 'error', 'amount'])
    df.to_csv(os.path.join(ap.OUT, 'positions_apex%d_shift%g.csv' % (args.apex, args.shift)), index=False)
    print('%d precursors, %d fragments, %.0f s (apex +/- %d sweeps)' % (len(tasks), len(df), time.time() - t0, args.apex))

    print('\nfragments: position error (fitted - precursor m/z, Th) by ions near the precursor')
    print('%-12s %7s %8s %8s %8s %8s %8s' % ('ions', 'n', 'found', 'median', '|err|50', '|err|68', '|err|95'))
    edges = [0, 3, 10, 30, 100, 300, 1e12]
    for lo, hi in zip(edges[:-1], edges[1:]):
        s = df[(df['ions'] > lo) & (df['ions'] <= hi)]
        e = s['error'].dropna()
        if len(s) == 0:
            continue
        q = np.quantile(np.abs(e), [0.5, 0.68, 0.95]) if len(e) else [np.nan] * 3
        print('%-12s %7d %7.0f%% %8.2f %8.2f %8.2f %8.2f' % ('%g-%g' % (lo, hi) if hi < 1e12 else '>%g' % lo, len(s),
              100 * len(e) / len(s), e.median() if len(e) else np.nan, *q))

    # The precursor: its found fragments' positions, weighted by their ions.
    found = df.dropna(subset=['error'])
    g = found.groupby('id')
    prec = pd.DataFrame({'ions': g['ions'].sum(), 'n': g.size(),
                         'error': g.apply(lambda s: np.average(s['error'], weights=s['ions']), include_groups=False)})
    print('\nprecursors: fragments combined by ions (%d of %d with a found fragment)' % (len(prec), len(tasks)))
    print('%-12s %7s %8s %8s %8s %8s' % ('ions', 'n', 'median', '|err|50', '|err|68', '|err|95'))
    for lo, hi in zip(edges[:-1], edges[1:]):
        s = prec[(prec['ions'] > lo) & (prec['ions'] <= hi)]['error']
        if len(s) == 0:
            continue
        q = np.quantile(np.abs(s), [0.5, 0.68, 0.95])
        print('%-12s %7d %8.2f %8.2f %8.2f %8.2f' % ('%g-%g' % (lo, hi) if hi < 1e12 else '>%g' % lo, len(s), s.median(), *q))


if __name__ == '__main__':
    main()
