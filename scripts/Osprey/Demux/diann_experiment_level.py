"""DIA-NN reports counted as Compare-DemuxSearches.py counts Osprey's: experiment-level identifications (DIA-NN's
Global.Q.Value, the q of a precursor across all runs) at several q, unique non-entrapment precursors and peptides
(a peptide passes if any of its precursors does), with FDRBench's combined entrapment FDP
N_e (1 + 1/r) / (N_t + N_e). Entrapment ids carry '_p_target'; r is the library's entrapment ratio.

Usage: python diann_experiment_level.py [--r 0.99986] <arm>=<report.parquet> [...]
"""
import argparse

import pandas as pd


def fdp(n_target, n_entrap, r):
    return n_entrap * (1 + 1 / r) / max(n_target + n_entrap, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--r', type=float, default=0.99986)
    ap.add_argument('--q', type=float, action='append')
    ap.add_argument('arms', nargs='+')
    args = ap.parse_args()
    qs = args.q or [0.01, 0.02, 0.03]
    print('%-10s %6s %10s %6s %7s %10s %6s %7s   %s' % ('arm', 'q', 'precursors', 'entrap', 'FDP', 'peptides', 'entrap',
                                                      'FDP', 'max run-level Q.Value in report'))
    for arm in args.arms:
        name, path = arm.split('=', 1)
        df = pd.read_parquet(path, columns=['Precursor.Id', 'Stripped.Sequence', 'Protein.Ids', 'Q.Value', 'Global.Q.Value'])
        df['entrap'] = df['Protein.Ids'].str.contains('_p_target', regex=False)
        prec = df.groupby('Precursor.Id').agg(q=('Global.Q.Value', 'min'), entrap=('entrap', 'first'),
                                              pep=('Stripped.Sequence', 'first'))
        pep = prec.groupby('pep').agg(q=('q', 'min'), entrap=('entrap', 'first'))
        for q in qs:
            p, s = prec[prec['q'] <= q], pep[pep['q'] <= q]
            pt, pe = int((~p['entrap']).sum()), int(p['entrap'].sum())
            st, se = int((~s['entrap']).sum()), int(s['entrap'].sum())
            print('%-10s %6.2f %10d %6d %6.2f%% %10d %6d %6.2f%%   %.4f' % (name, q, pt, pe, 100 * fdp(pt, pe, args.r),
                                                                        st, se, 100 * fdp(st, se, args.r),
                                                                        df['Q.Value'].max()))


if __name__ == '__main__':
    main()
