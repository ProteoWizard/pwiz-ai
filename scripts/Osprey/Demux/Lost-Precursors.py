"""Which precursors does a demux arm lose against raw? Compares, per run, the raw arm's target
precursors (Q <= 0.01, RT in the core) found and not found by the demux arm: their raw quantity,
their precursor m/z offset from the center of its encoded bin, and their charge.

Usage: python Lost-Precursors.py --rt lo hi <raw report.parquet> <demux report.parquet>
"""
import argparse

import numpy as np
import pandas as pd

STEP, FIRST = 1.181866, 392.760634


def load(path, lo, hi):
    df = pd.read_parquet(path, columns=['Run', 'Precursor.Id', 'Protein.Ids', 'Q.Value', 'RT', 'Precursor.Mz',
                                        'Precursor.Charge', 'Precursor.Quantity'])
    return df[(df['Q.Value'] <= 0.01) & (df['RT'] >= lo) & (df['RT'] <= hi)
              & ~df['Protein.Ids'].str.contains('_p_target', regex=False)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rt', type=float, nargs=2, required=True)
    ap.add_argument('raw')
    ap.add_argument('demux')
    args = ap.parse_args()
    raw = load(args.raw, *args.rt)
    dem = load(args.demux, *args.rt)
    rows = []
    for run, g in raw.groupby('Run'):
        found = set(dem[dem['Run'] == run]['Precursor.Id'])
        g = g.drop_duplicates('Precursor.Id').copy()
        g['kept'] = g['Precursor.Id'].isin(found)
        rows.append(g)
    df = pd.concat(rows)
    q = np.log10(df['Precursor.Quantity'].clip(lower=1))
    edges = np.quantile(q, [0, 0.25, 0.5, 0.75, 1])
    print('raw targets %d, kept by demux %.1f%%' % (len(df), 100 * df['kept'].mean()))
    print('by raw quantity quartile:')
    for k in range(4):
        m = (q >= edges[k]) & (q <= edges[k + 1])
        print('  Q%d (log10 %.1f-%.1f): kept %.1f%% of %d' % (k + 1, edges[k], edges[k + 1], 100 * df['kept'][m].mean(),
                                                           m.sum()))
    off = (df['Precursor.Mz'] - FIRST) / STEP % 1.0 - 0.5  # -0.5..0.5 of a bin from its center
    print('by precursor offset from its bin center (fraction of a bin):')
    for lo, hi in ((0, 0.15), (0.15, 0.3), (0.3, 0.5)):
        m = (off.abs() >= lo) & (off.abs() < hi)
        print('  |offset| %.2f-%.2f: kept %.1f%% of %d' % (lo, hi, 100 * df['kept'][m].mean(), m.sum()))
    print('by charge:')
    for z, g in df.groupby('Precursor.Charge'):
        print('  %d+: kept %.1f%% of %d' % (z, 100 * g['kept'].mean(), len(g)))


if __name__ == '__main__':
    main()
