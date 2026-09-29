"""Compare DIA-NN searches of ZT Scan slices (raw, DIA-NN scanning mode, our demux) on
identification and replicate quantitation.

Usage: python Compare-ZtScanSlices.py --rt lo hi <arm>=<report.parquet> [...]

Per arm and run: target precursors at Q.Value <= 0.01 with RT in [lo, hi] (the slice's core), and
the entrapment FDP (FDRBench combined: N_e (1 + 1/r) / (N_t + N_e); entrapment ids carry
'_p_target'). Then replicate precision: the CV of Precursor.Quantity across the runs, for target
precursors identified in every run, per arm on its own set and on the set every arm shares.
"""
import argparse

import numpy as np
import pandas as pd

R = 0.99986
Q = 0.01


def load(path, rt_lo, rt_hi):
    cols = ['Run', 'Precursor.Id', 'Protein.Ids', 'Q.Value', 'RT', 'Precursor.Quantity']
    df = pd.read_parquet(path, columns=cols)
    df = df[(df['Q.Value'] <= Q) & (df['RT'] >= rt_lo) & (df['RT'] <= rt_hi)].copy()
    df['entrapment'] = df['Protein.Ids'].str.contains('_p_target', regex=False)
    return df


def cv_table(df, runs):
    t = df[~df['entrapment']].pivot_table(index='Precursor.Id', columns='Run', values='Precursor.Quantity',
                                         aggfunc='max')
    t = t.reindex(columns=runs).dropna()
    t = t[(t > 0).all(axis=1)]
    return t.std(axis=1, ddof=1) / t.mean(axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rt', type=float, nargs=2, required=True)
    ap.add_argument('arms', nargs='+')
    args = ap.parse_args()
    arms = []
    for a in args.arms:
        name, path = a.split('=', 1)
        arms.append((name, load(path, *args.rt)))

    print('%-16s %-40s %8s %7s %7s' % ('arm', 'run', 'targets', 'entrap', 'FDP'))
    for name, df in arms:
        for run, g in df.groupby('Run'):
            p = g.drop_duplicates('Precursor.Id')
            n_e = int(p['entrapment'].sum())
            n_t = len(p) - n_e
            print('%-16s %-40s %8d %7d %6.2f%%' % (name, run, n_t, n_e, 100 * n_e * (1 + 1 / R) / max(n_t + n_e, 1)))

    cvs = {}
    for name, df in arms:
        runs = sorted(df['Run'].unique())
        cvs[name] = cv_table(df, runs)
    shared = set.intersection(*(set(c.index) for c in cvs.values()))
    print('\nreplicate CV of Precursor.Quantity (targets identified in every run)')
    print('%-16s %8s %8s %8s %8s | %8s %8s' % ('arm', 'n', 'median', 'p25', 'p75', 'shared n', 'median'))
    for name, c in cvs.items():
        s = c[c.index.isin(shared)]
        print('%-16s %8d %8.3f %8.3f %8.3f | %8d %8.3f' % (name, len(c), c.median(), c.quantile(0.25), c.quantile(0.75),
                                                          len(s), s.median() if len(s) else float('nan')))


if __name__ == '__main__':
    main()
