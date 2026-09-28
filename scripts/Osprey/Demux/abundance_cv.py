"""Replicate CV by abundance quartile, on the target precursors every arm identifies in every run: quartiles of
the first arm's mean Precursor.Quantity. If an arm's advantage comes from signal the others lose at the lowest
ion counts, it should be largest in the lowest quartile.

Usage: python abundance_cv.py <arm>=<report.parquet> [...]
"""
import sys

import numpy as np
import pandas as pd

from region_cv import load


def main():
    arms = [a.split('=', 1) for a in sys.argv[1:]]
    loaded = [(name, *load(path)) for name, path in arms]
    shared = sorted(set.intersection(*(set(q.index) for _, q, _ in loaded)))
    mean0 = loaded[0][1].loc[shared].mean(axis=1)
    quartile = pd.qcut(mean0, 4, labels=['Q1 (low)', 'Q2', 'Q3', 'Q4 (high)'])
    print('%d precursors shared; quartiles of %s mean quantity' % (len(shared), loaded[0][0]))
    print('%-10s %6s ' % ('quartile', 'n') + ' '.join('%10s' % name for name, _, _ in loaded))
    cvs = {}
    for name, q, _ in loaded:
        v = q.loc[shared].to_numpy()
        cvs[name] = pd.Series(v.std(axis=1, ddof=1) / v.mean(axis=1), index=shared)
    for label in ['Q1 (low)', 'Q2', 'Q3', 'Q4 (high)']:
        idx = quartile.index[quartile == label]
        print('%-10s %6d ' % (label, len(idx)) + ' '.join('%10.3f' % cvs[name].loc[idx].median() for name, _, _ in loaded))


if __name__ == '__main__':
    main()
