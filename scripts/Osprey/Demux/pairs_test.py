"""Complementary b/y pairs on ZT Scan: how often are both ions of a pair observed, how precisely does an
observed pair give the precursor's mass, and how many peaks compete for the partner when the
precursor m/z is known only from its fragments' Q1 profile?

For the precursors DIA-NN identified on A1 in the slice: every library pair b_i / y_(n-i), both 1+ with
no loss, is a complementary pair; b + y = M + 2 H+ (M the neutral precursor mass). Each ion's peaks
within +/- TOL_PPM are summed over the sweeps around DIA-NN's apex in the encoded bins near the
precursor (as position_test.py), with their intensity-weighted m/z. A pair is observed when both ions
have at least MIN_IONS. For an observed pair, the pair gives M = b + y - 2 H+, compared with the library
precursor mass in ppm. Competition: the peaks (at least 1 ion) in the precursor's own bin at the apex
within the window a +/- 0.5 Th precursor position allows for the partner (+/- z * 0.5 Da).

Usage: python pairs_test.py [--workers 6]
"""
import argparse
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anchored_prototype as ap  # noqa: E402
from ztscan_real import FIRST, STEP  # noqa: E402

PROTON = 1.007276
MIN_IONS = 10.0
POSITION_SD = 0.5   # Th: the precursor position the Q1 profile gives
APEX = 2


def init():
    ap.init_worker(None)


def observe(task):
    pid, mz, z, ci0, pairs = task
    key, csum, rt = ap._state['key'], ap._state['csum'], ap._state['rt']
    rr = ap._state['rows_rel']
    nb = ap.BINS[1] - ap.BINS[0] + 1
    pbin, _ = ap.bin_of(mz)
    near = np.abs(rr) <= ap.REACH
    sweeps = np.arange(max(0, ci0 - APEX), min(len(rt), ci0 + APEX + 1))
    spec = (sweeps[None, :] * nb + (pbin + rr[near] - ap.BINS[0])[:, None]).astype(np.float64).ravel()
    tol = ap.TOL_PPM * 1e-6

    def ion(target):
        lo = np.searchsorted(key, spec * 1e4 + target * (1 - tol))
        hi = np.searchsorted(key, spec * 1e4 + target * (1 + tol), side='right')
        ions, weighted = 0.0, 0.0
        for s, a, b in zip(spec, lo, hi):
            if b > a:
                v = np.diff(csum[a:b + 1])
                m = np.asarray(key[a:b]) - s * 1e4
                ions += v.sum()
                weighted += (v * m).sum()
        return ions, (weighted / ions if ions > 0 else np.nan)

    # The own bin's apex spectrum, for counting the peaks competing for a partner.
    own = float(ci0 * nb + pbin - ap.BINS[0])
    a = np.searchsorted(key, own * 1e4)
    b = np.searchsorted(key, (own + 1) * 1e4)
    own_mz = np.asarray(key[a:b]) - own * 1e4
    own_ions = np.diff(csum[a:b + 1])
    mass = z * (mz - PROTON)
    out = []
    for bmz, ymz in pairs:
        bi, bm = ion(bmz)
        yi, ym = ion(ymz)
        both = bi >= MIN_IONS and yi >= MIN_IONS
        ppm = ((bm + ym - 2 * PROTON) - mass) / mass * 1e6 if both else np.nan
        # Partner of the stronger ion, when the precursor is known to +/- POSITION_SD Th.
        strong, partner = (bmz, ymz) if bi >= yi else (ymz, bmz)
        half = z * POSITION_SD
        competing = int(((np.abs(own_mz - partner) <= half) & (own_ions >= 1)).sum())
        out.append((pid, z, bi, yi, both, ppm, competing))
    return out


def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('--workers', type=int, default=6)
    args = argp.parse_args()
    key, csum, rt = ap.load_slice(args.workers)
    rep = pd.read_parquet(ap.RT_REPORT, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Q.Value'])
    rep = rep[(rep['Q.Value'] <= 0.01) & rep['Precursor.Mz'].between(*ap.MZ_RANGE) & rep['RT'].between(*ap.RT_RANGE)]
    rep = rep.drop_duplicates('Precursor.Id').set_index('Precursor.Id')
    frag = pq.read_table(ap.LIB, columns=['Precursor.Id', 'Stripped.Sequence', 'Precursor.Charge', 'Product.Mz',
                                          'Fragment.Type', 'Fragment.Charge', 'Fragment.Series.Number',
                                          'Fragment.Loss.Type'],
                         filters=[('Precursor.Id', 'in', list(rep.index))]).to_pandas()
    per_prec = frag.groupby('Precursor.Id').size()
    print('library fragments per precursor: median %d (%d-%d)' % (per_prec.median(), per_prec.min(), per_prec.max()))
    single = frag[(frag['Fragment.Charge'] == 1) & (frag['Fragment.Loss.Type'] == 'noloss')]
    tasks, with_pair = [], 0
    for pid, g in single.groupby('Precursor.Id', sort=True):
        n = len(g['Stripped.Sequence'].iloc[0])
        ys = dict(zip(g.loc[g['Fragment.Type'] == 'y', 'Fragment.Series.Number'], g.loc[g['Fragment.Type'] == 'y', 'Product.Mz']))
        pairs = [(bmz, ys[n - i]) for i, bmz in zip(g.loc[g['Fragment.Type'] == 'b', 'Fragment.Series.Number'],
                                                    g.loc[g['Fragment.Type'] == 'b', 'Product.Mz']) if (n - i) in ys]
        if not pairs:
            continue
        with_pair += 1
        r = rep.loc[pid]
        ci0 = int(np.argmin(np.abs(np.asarray(rt) - r['RT'])))
        tasks.append((pid, float(r['Precursor.Mz']), int(g['Precursor.Charge'].iloc[0]), ci0, pairs))
    print('%d identified precursors; %d have a complementary 1+ b/y pair among their library fragments' %
          (len(rep), with_pair))
    t0 = time.time()
    rows = []
    with ProcessPoolExecutor(max_workers=args.workers, initializer=init) as ex:
        for part in ex.map(observe, tasks, chunksize=16):
            rows.extend(part)
    df = pd.DataFrame(rows, columns=['id', 'z', 'b_ions', 'y_ions', 'both', 'ppm', 'competing'])
    df.to_csv(os.path.join(ap.OUT, 'pairs.csv'), index=False)
    print('%d library pairs checked in %.0f s' % (len(df), time.time() - t0))

    by = df.groupby('id')
    prec = pd.DataFrame({'z': by['z'].first(), 'pairs': by.size(), 'observed': by['both'].sum()})
    print('\nprecursors with at least one observed pair (both ions >= %g ions near the apex): %d of %d (%.0f%%)' %
          (MIN_IONS, (prec['observed'] > 0).sum(), len(prec), 100 * (prec['observed'] > 0).mean()))
    for z, s in prec.groupby('z'):
        print('  charge %d: %d of %d; median library pairs %d, observed %d' %
              (z, (s['observed'] > 0).sum(), len(s), s['pairs'].median(), s['observed'].median()))
    obs = df[df['both']]
    weaker = np.minimum(obs['b_ions'], obs['y_ions'])
    print('observed pairs: %d; weaker ion median %.0f ions; b/y ions median %.0f / %.0f' %
          (len(obs), weaker.median(), obs['b_ions'].median(), obs['y_ions'].median()))
    e = obs['ppm']
    print('precursor mass from the pair: error median %+.1f ppm, |err| 50%% %.1f, 68%% %.1f, 95%% %.1f ppm' %
          (e.median(), *np.quantile(np.abs(e - e.median()), [0.5, 0.68, 0.95])))
    c = obs['competing']
    print('peaks in the own-bin apex spectrum within the partner window (+/- z x %.1f Da): median %d, 90%% %d' %
          (POSITION_SD, c.median(), c.quantile(0.9)))


if __name__ == '__main__':
    main()
