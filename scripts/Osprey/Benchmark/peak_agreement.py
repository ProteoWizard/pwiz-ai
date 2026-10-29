"""Does Osprey's first-step peak pick choose the peak DIA-NN scores? (TODO-20261028_osprey_diann_fdr_gap.md)

For each run and each precursor DIA-NN identifies in it (run Q.Value <= --diann-q, real targets only - entrapment
excluded through the peptide FASTA), compares DIA-NN's peak (RT, RT.Start, RT.Stop) with the peak Osprey's first
pass chose for the same precursor in the same run (<run>.scores.parquet: apex_rt, start_rt, end_rt) and with the
top-N CWT candidates Osprey kept (cwt_candidates: count, then apex, start, end, area, snr, coelution per candidate):

  same peak        DIA-NN's apex inside Osprey's chosen bounds, or Osprey's apex inside DIA-NN's
  wrong pick       not the same peak, but DIA-NN's apex inside one of Osprey's kept candidates
  not a candidate  DIA-NN's apex inside none of Osprey's kept candidates
  not scored       no Osprey row for the precursor in that run

Split by whether Osprey's first pass reports the precursor at its experiment q for --osprey-fdp (both) or not
(DIA-NN only), with q from the pass-1 FDRBench export.

Usage:
  peak_agreement.py <work dir> <out dir> [--osprey osprey] [--diann diann-search-nombr] [--diann-q 0.01]
                    [--osprey-q 0.004739]
"""
import argparse
import glob
import os
import struct
import sys

import numpy as np
import pandas as pd
import pyarrow.compute as pc
import pyarrow.parquet as pq

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plot_entrapment import load_space, stripped  # noqa: E402
from plot_diann_comparison import run_label  # noqa: E402


def candidates(blob):
    """(apex, start, end) arrays of the kept CWT candidates."""
    if not isinstance(blob, (bytes, bytearray)) or len(blob) < 4:   # NaN for a precursor Osprey did not score
        return np.empty((0, 3))
    n = min(struct.unpack_from('<I', blob)[0], (len(blob) - 4) // 48)
    a = np.frombuffer(blob, dtype='<f8', count=n * 6, offset=4).reshape(n, 6)
    return a[:, :3]


def classify(d_rt, d_start, d_stop, o_apex, o_start, o_end, blob):
    if np.isnan(o_apex):
        return 'not scored'
    if o_start <= d_rt <= o_end or d_start <= o_apex <= d_stop:
        return 'same peak'
    c = candidates(blob)
    if len(c) and np.any((c[:, 1] <= d_rt) & (d_rt <= c[:, 2])):
        return 'wrong pick'
    return 'not a candidate'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('work_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--osprey', default='osprey')
    ap.add_argument('--diann', default='diann-search-nombr')
    ap.add_argument('--diann-q', type=float, default=0.01)
    ap.add_argument('--osprey-q', type=float, default=0.004739,
                    help="Osprey pass-1 experiment q for 'both' (default: its q at entrapment FDP 0.5%%)")
    ap.add_argument('--suffix', default='_p_target')
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    entrap, _, _ = load_space(os.path.join(args.work_dir, 'peptides', 'target_entrapment_peptides.fasta'),
                              args.suffix)
    odir = os.path.join(args.work_dir, args.osprey)
    p1 = pd.read_csv(os.path.join(odir, 'FDRBench-Input.pass1.tsv'), sep='\t', usecols=['peptide', 'charge', 'q_value'])
    osprey_ids = set(zip(p1.loc[p1['q_value'] <= args.osprey_q, 'peptide'], p1.loc[p1['q_value'] <= args.osprey_q, 'charge']))
    osprey_q = dict(zip(zip(p1['peptide'], p1['charge']), p1['q_value']))

    d = pd.read_parquet(os.path.join(args.work_dir, args.diann, 'report.parquet'),
                        columns=['Run', 'Stripped.Sequence', 'Precursor.Charge', 'RT', 'RT.Start', 'RT.Stop', 'FWHM',
                                 'Q.Value', 'Precursor.Quantity'])
    d = d[d['Q.Value'] <= args.diann_q]
    d = d[~d['Stripped.Sequence'].map(lambda s: entrap.get(stripped(s), False))]
    d['run'] = d['Run'].map(run_label)
    d['charge'] = d['Precursor.Charge'].astype(int)

    rows = []
    for path in sorted(glob.glob(os.path.join(odir, '*.scores.parquet'))):
        run = run_label(os.path.basename(path).replace('.scores.parquet', ''))
        dr = d[d['run'] == run]
        if dr.empty:
            continue
        keys = set(dr['Stripped.Sequence'])
        t = pq.read_table(path, columns=['sequence', 'charge', 'is_decoy', 'apex_rt', 'start_rt', 'end_rt',
                                         'cwt_candidates'])
        t = t.filter(pc.and_(pc.invert(t['is_decoy']), pc.is_in(t['sequence'], value_set=pa_strings(keys))))
        o = t.to_pandas().drop_duplicates(['sequence', 'charge'])
        m = dr.merge(o, how='left', left_on=['Stripped.Sequence', 'charge'], right_on=['sequence', 'charge'])
        m['class'] = [classify(*v) for v in zip(m['RT'], m['RT.Start'], m['RT.Stop'], m['apex_rt'].astype(float),
                                                m['start_rt'].astype(float), m['end_rt'].astype(float),
                                                m['cwt_candidates'])]
        key = list(zip(m['Stripped.Sequence'], m['charge']))
        m['osprey'] = ['both' if k in osprey_ids else 'DIA-NN only' for k in key]
        m['osprey_pass1_q'] = [osprey_q.get(k, np.nan) for k in key]
        m['delta_apex'] = m['apex_rt'] - m['RT']
        m['n_candidates'] = [len(candidates(b)) for b in m['cwt_candidates']]
        rows.append(m.drop(columns=['cwt_candidates', 'sequence', 'Run']))
    allm = pd.concat(rows, ignore_index=True)
    allm.to_parquet(os.path.join(args.out_dir, 'peak_agreement.parquet'))

    order = ['same peak', 'wrong pick', 'not a candidate', 'not scored']
    lines = [f'DIA-NN {args.diann} at run Q.Value <= {args.diann_q}, real targets; Osprey {args.osprey} first pass, '
             f"'both' = Osprey pass-1 experiment q <= {args.osprey_q}", '']
    for (run, grp), g in allm.groupby(['run', 'osprey']):
        counts = g['class'].value_counts()
        lines.append(f'run {run} {grp:12s} n={len(g):7d}  ' + '  '.join(
            f'{c} {counts.get(c, 0) / len(g):6.1%}' for c in order))
    lines.append('')
    for grp, g in allm.groupby('osprey'):
        counts = g['class'].value_counts()
        lines.append(f'all runs {grp:12s} n={len(g):7d}  ' + '  '.join(
            f'{c} {counts.get(c, 0):7d} ({counts.get(c, 0) / len(g):5.1%})' for c in order))
    for grp, g in allm.groupby('osprey'):
        wrong = g[g['class'].isin(['wrong pick', 'not a candidate'])]
        if len(wrong):
            lines.append(f'{grp}: |apex difference| of the different-peak picks, min: ' + ', '.join(
                f'{p}%={wrong["delta_apex"].abs().quantile(p / 100):.2f}' for p in (10, 25, 50, 75, 90)))
        same = g[g['class'] == 'same peak']
        if len(same):
            lines.append(f'{grp}: Osprey pass-1 q of same-peak precursors: ' + ', '.join(
                f'{p}%={same["osprey_pass1_q"].quantile(p / 100):.3g}' for p in (10, 25, 50, 75, 90)))
    text = '\n'.join(lines)
    with open(os.path.join(args.out_dir, 'peak_agreement.txt'), 'w') as f:
        f.write(text + '\n')
    print(text)


def pa_strings(values):
    import pyarrow as pa
    return pa.array(sorted(values), type=pa.string())


if __name__ == '__main__':
    main()
