"""Is Osprey's run-level PEP calibrated? (TODO-20261028_osprey_diann_fdr_gap.md, the run PEP of reconciled peaks)

Reads the OSPREY_DUMP_RUN_PEP folder (<run>.run_pep.tsv: modified_sequence, charge, is_decoy, class, score, run_q,
run_pep - one row per compaction survivor per run, class Unchanged / Moved / GapFill) and the peptide FASTA both
tools searched. For targets (entrapment counted as targets, as Osprey sees them), per class and PEP bin, compares
the mean run PEP with the entrapment-estimated false fraction N_e (1 + 1/r) / N - the combined estimator, an upper
bound; the lower bound is N_e / (r N). A calibrated PEP sits between them.

With --pass1 <FDRBench-Input.pass1.tsv> (a --fdrbench-per-run export) it also reads each run's
<run>.run_pep_curve.tsv and applies it to EVERY first-pass target peak - the population where entrapment really is 1:1,
so the per-bin comparison is fair - and checks the q-PEP identity there: the mean PEP of the peaks at run q <= t must
not exceed t.

Usage:
  run_pep_calibration.py <dump dir> <peptide fasta> [--suffix _p_target] [--pass1 <FDRBench-Input.pass1.tsv>]
"""
import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plot_entrapment import load_space, stripped  # noqa: E402

BINS = (0.0, 0.01, 0.05, 0.2, 0.5, 0.9, 0.99, 1.0000001)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dump_dir')
    ap.add_argument('peptide_fasta')
    ap.add_argument('--suffix', default='_p_target')
    ap.add_argument('--pass1')
    args = ap.parse_args()
    if args.pass1:
        full_population(args)
        return
    entrap, r, _ = load_space(args.peptide_fasta, args.suffix)
    frames = []
    for path in sorted(glob.glob(os.path.join(args.dump_dir, '*.run_pep.tsv'))):
        d = pd.read_csv(path, sep='\t')
        d['run'] = os.path.basename(path).replace('.run_pep.tsv', '')
        frames.append(d)
    d = pd.concat(frames, ignore_index=True)
    d = d[d['is_decoy'] == 0].copy()
    d['entrap'] = d['modified_sequence'].map(lambda s: entrap.get(stripped(s), False))
    d['bin'] = pd.cut(d['run_pep'], BINS, right=False)
    print(f'{len(d)} target rows over {d["run"].nunique()} runs; r = {r:.4f}')
    for cls, g in [('all', d)] + list(d.groupby('class')):
        print(f'\n{cls}: {len(g)} rows, mean run PEP {g["run_pep"].mean():.3f}, '
              f'entrapment-estimated false {g["entrap"].sum() * (1 + 1 / r) / len(g):.3f}')
        print(f'  {"PEP bin":16s} {"rows":>8s} {"mean PEP":>9s} {"false (comb)":>13s} {"false (lower)":>14s} {"run q<=1%":>10s}')
        for b, x in g.groupby('bin', observed=True):
            n = len(x)
            ne = int(x['entrap'].sum())
            print(f'  {str(b):16s} {n:8d} {x["run_pep"].mean():9.4f} {ne * (1 + 1 / r) / n:13.4f} '
                  f'{ne / (r * n):14.4f} {int((x["run_q"] <= 0.01).sum()):10d}')


def full_population(args):
    from plot_diann_comparison import run_label
    entrap, r, _ = load_space(args.peptide_fasta, args.suffix)
    p1 = pd.read_csv(args.pass1, sep='\t', usecols=['peptide', 'q_value', 'score', 'run'])
    p1['run'] = p1['run'].map(run_label)
    p1['entrap'] = p1['peptide'].map(lambda s: entrap.get(stripped(s), False))
    curves = {}
    for path in glob.glob(os.path.join(args.dump_dir, '*.run_pep_curve.tsv')):
        c = pd.read_csv(path, sep='\t')
        curves[run_label(os.path.basename(path).replace('.run_pep_curve.tsv', ''))] = c
    parts = []
    for run, g in p1.groupby('run'):
        c = curves[run]
        g = g.copy()
        g['run_pep'] = np.interp(g['score'], c['score'], c['run_pep'])
        parts.append(g)
    d = pd.concat(parts, ignore_index=True)
    print(f'{len(d)} first-pass target peaks over {d["run"].nunique()} runs; r = {r:.4f}')
    print('q-PEP identity (mean PEP of peaks at run q <= t must not exceed t):')
    for t in (0.001, 0.005, 0.01, 0.05):
        x = d[d['q_value'] <= t]
        ne = int(x['entrap'].sum())
        print(f'  run q <= {t:<6}: {len(x):8d} peaks, mean PEP {x["run_pep"].mean():.4f}, '
              f'entrapment FDP {ne * (1 + 1 / r) / max(len(x), 1):.4f} (lower {ne / (r * max(len(x), 1)):.4f})')
    d['bin'] = pd.cut(d['run_pep'], BINS, right=False)
    print(f'  {"PEP bin":16s} {"peaks":>9s} {"mean PEP":>9s} {"false (comb)":>13s} {"false (lower)":>14s}')
    for b, x in d.groupby('bin', observed=True):
        ne = int(x['entrap'].sum())
        print(f'  {str(b):16s} {len(x):9d} {x["run_pep"].mean():9.4f} {ne * (1 + 1 / r) / len(x):13.4f} '
              f'{ne / (r * len(x)):14.4f}')


if __name__ == '__main__':
    main()
