"""Identification summary of DIA-NN arms: per run, target precursors and target peptides (unique stripped
sequences) at Q.Value <= 0.01, the entrapment FDP of each (FDRBench combined, entrapment ids carry '_p_target'),
and over the runs the peptides found in every run and in any run.

Usage: python ids_summary.py [--rt lo hi] <arm>=<report.parquet> [...]
"""
import argparse

import pandas as pd

R = 0.99986


def fdp(n_target, n_entrap):
    return n_entrap * (1 + 1 / R) / max(n_target + n_entrap, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rt', type=float, nargs=2, default=[0, 1e9])
    ap.add_argument('arms', nargs='+')
    args = ap.parse_args()
    print('%-12s %-30s %9s %7s %9s %7s' % ('arm', 'run', 'prec', 'FDP', 'peptides', 'FDP'))
    summary = []
    for arm in args.arms:
        name, path = arm.split('=', 1)
        df = pd.read_parquet(path, columns=['Run', 'Precursor.Id', 'Stripped.Sequence', 'Protein.Ids', 'Q.Value', 'RT'])
        df = df[(df['Q.Value'] <= 0.01) & df['RT'].between(*args.rt)].copy()
        df['entrap'] = df['Protein.Ids'].str.contains('_p_target', regex=False)
        per_run = []
        for run, g in df.groupby('Run', sort=True):
            t, e = g[~g['entrap']], g[g['entrap']]
            pt, pe = t['Stripped.Sequence'].nunique(), e['Stripped.Sequence'].nunique()
            print('%-12s %-30s %9d %6.2f%% %9d %6.2f%%' % (name, run[-28:], t['Precursor.Id'].nunique(),
                                                         100 * fdp(len(t), len(e)), pt, 100 * fdp(pt, pe)))
            per_run.append(set(t['Stripped.Sequence']))
        summary.append((name, len(set.intersection(*per_run)), len(set.union(*per_run))))
    print('\n%-12s %14s %12s' % ('arm', 'peptides, all', 'any run'))
    for name, every, anyrun in summary:
        print('%-12s %14d %12d' % (name, every, anyrun))


if __name__ == '__main__':
    main()
