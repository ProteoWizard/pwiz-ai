"""Where a whole-run quantitation gap lives: the median replicate CV of Precursor.Quantity by RT and
precursor m/z cell, per arm, on the target precursors every arm identifies in every run (1% FDR).

Usage: python region_cv.py <arm>=<report.parquet> [...]
"""
import sys

import numpy as np
import pandas as pd

RT_EDGES = [0, 2, 4, 6, 8, 10, 12, 30]
MZ_EDGES = [390, 500, 600, 700, 800, 900]


def load(path):
    df = pd.read_parquet(path, columns=['Run', 'Precursor.Id', 'Protein.Ids', 'Q.Value', 'RT', 'Precursor.Mz',
                                        'Precursor.Quantity'])
    df = df[(df['Q.Value'] <= 0.01) & ~df['Protein.Ids'].str.contains('_p_target', regex=False)]
    q = df.pivot_table(index='Precursor.Id', columns='Run', values='Precursor.Quantity', aggfunc='max').dropna()
    meta = df.groupby('Precursor.Id')[['RT', 'Precursor.Mz']].median()
    return q, meta


def main():
    arms = [a.split('=', 1) for a in sys.argv[1:]]
    loaded = [(name, *load(path)) for name, path in arms]
    shared = set.intersection(*(set(q.index) for _, q, _ in loaded))
    shared = sorted(shared)
    meta = loaded[0][2].loc[shared]
    rt_bin = pd.cut(meta['RT'], RT_EDGES)
    mz_bin = pd.cut(meta['Precursor.Mz'], MZ_EDGES)
    print('%d precursors shared by all arms' % len(shared))
    cv = {}
    for name, q, _ in loaded:
        v = q.loc[shared].to_numpy()
        cv[name] = pd.Series(v.std(axis=1, ddof=1) / v.mean(axis=1), index=shared)
        print('%-12s overall median CV %.3f' % (name, cv[name].median()))
    for by, bins in (('RT (min)', rt_bin), ('precursor m/z', mz_bin)):
        print('\nmedian CV by %s' % by)
        print('%-14s %6s ' % ('cell', 'n') + ' '.join('%10s' % name for name, _, _ in loaded))
        for cell, idx in bins.groupby(bins, observed=True).groups.items():
            idx = list(idx)
            print('%-14s %6d ' % (cell, len(idx)) + ' '.join('%10.3f' % cv[name].loc[idx].median()
                                                              for name, _, _ in loaded))


if __name__ == '__main__':
    main()
