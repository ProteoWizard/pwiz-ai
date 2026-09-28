"""Paired comparison of DIA-NN slice arms on the target precursors every arm identifies in every run:
per-precursor CV of Precursor.Quantity, the median paired difference against the first arm and the
share improved, and how far each arm's quantities for the same run move from the first arm's
(median |log2 ratio|), which shows how much DIA-NN's quantity itself shifts between searches.

Usage: python paired_cv.py --rt lo hi <arm>=<report.parquet> [...]
"""
import argparse

import numpy as np
import pandas as pd


def load(path, lo, hi):
    df = pd.read_parquet(path, columns=['Run', 'Precursor.Id', 'Protein.Ids', 'Q.Value', 'RT', 'Precursor.Quantity'])
    df = df[(df['Q.Value'] <= 0.01) & (df['RT'] >= lo) & (df['RT'] <= hi)]
    df = df[~df['Protein.Ids'].str.contains('_p_target', regex=False)]
    return df.pivot_table(index='Precursor.Id', columns='Run', values='Precursor.Quantity', aggfunc='max')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rt', type=float, nargs=2, required=True)
    ap.add_argument('arms', nargs='+')
    args = ap.parse_args()
    names, tables = [], []
    for arm in args.arms:
        name, path = arm.split('=', 1)
        names.append(name)
        tables.append(load(path, *args.rt))
    shared = None
    for t in tables:
        full = set(t.dropna().index)
        shared = full if shared is None else shared & full
    shared = sorted(shared)
    runs = sorted(tables[0].columns)
    cvs = []
    for t in tables:
        v = t.loc[shared, runs].to_numpy()
        cvs.append(v.std(axis=1, ddof=1) / v.mean(axis=1))
    base = tables[0].loc[shared, runs].to_numpy()
    print('%d shared precursors' % len(shared))
    print('%-14s %8s %10s %9s %14s' % ('arm', 'medCV', 'med dCV', 'improved', 'med|log2 q/q0|'))
    for name, t, cv in zip(names, tables, cvs):
        v = t.loc[shared, runs].to_numpy()
        d = cv - cvs[0]
        shift = np.median(np.abs(np.log2(v / base)))
        print('%-14s %8.4f %+10.4f %8.1f%% %14.3f' % (name, np.median(cv), np.median(d), 100 * np.mean(d < 0), shift))


if __name__ == '__main__':
    main()
