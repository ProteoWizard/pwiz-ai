"""Osprey vs DIA-NN FDR calibration and the compaction trace (TODO-20261028_osprey_diann_fdr_gap.md).

Reads a Run-DiannEntrapment.ps1 work folder: DIA-NN's diann-search\\report.parquet and every Osprey folder
holding an FDRBench export (the 'osprey' step and each 'osprey-arm'), written with --fdrbench-pass both
(FDRBench-Input.pass1.tsv, FDRBench-Input.pass2.tsv) or one pass (FDRBench-Input.tsv, taken as pass 2).

  pass 1  every precursor the first pass scored, before compaction, with its first-pass q - a fair
          sample of the whole q range
  pass 2  the compaction survivors with their reported (second-pass) q - fair only up to the q where
          compaction starts dropping entrapment (about 0.015)

An export with a 'run' column (--fdrbench-per-run) is a run-level table: one row per precursor and run.

FDP estimators (Wen et al. 2025): combined N_e (1 + 1/r) / (N_t + N_e) and lower bound
N_e / (r (N_t + N_e)), r = entrapment / target peptides searched.

Writes, into <out dir>:
  calibration.png   reported q vs FDP (combined solid, lower bound dashed) for q up to --max-q
  summary.tsv       per source: IDs and FDP at q 1%, IDs at matched FDP levels, protein groups
  trace.tsv         (with --trace-arm) each DIA-NN-only precursor at --trace-fdp: where Osprey lost it
  summary.txt       the same, readable

Usage:
  fdr_gap_analysis.py <work dir> <out dir> [--suffix _p_target] [--max-q 0.05] [--trace-arm osprey]
"""
import argparse
import glob
import os
import sqlite3
import sys

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plot_entrapment import (load_space, is_entrapment_group, stripped, at_fdp, at_q,  # noqa: E402
                             fdp_curve)
from plot_diann_comparison import run_label  # noqa: E402

NOMINAL = 0.01
LEVELS = (0.003, 0.005, 0.0075, 0.01)
PASS2_FAIR_Q = 0.015


def curve(table, r):
    """(q, n_t, combined FDP, lower-bound FDP) over the distinct q thresholds of a table."""
    q, n_t, comb = fdp_curve(table['q'].values, table['entrap'].values, r)
    # combined = N_e (1 + r) / (r (N_t + N_e)), so the lower bound N_e / (r (N_t + N_e)) = combined / (1 + r).
    return q, n_t, comb, comb / (1 + r)


def label(df, entrap):
    df['entrap'] = df['seq'].map(lambda s: entrap.get(stripped(s), False))
    return df


def load_fdrbench(path, entrap):
    df = pd.read_csv(path, sep='\t')
    out = pd.DataFrame({'seq': df['peptide'], 'z': df['charge'].astype(int), 'q': df['q_value'].astype(float),
                        'score': df['score'].astype(float)})
    out['key'] = list(zip(out['seq'], out['z']))
    if 'run' in df.columns:
        out['run'] = df['run'].map(run_label)
    return label(out, entrap)


def osprey_sources(folder, entrap):
    """name -> table for one Osprey folder: experiment pass 1 / pass 2 (or run level), and its proteins."""
    out = {}
    p1, p2 = (os.path.join(folder, f'FDRBench-Input.pass{n}.tsv') for n in (1, 2))
    single = os.path.join(folder, 'FDRBench-Input.tsv')
    for name, path in (('pass1', p1), ('pass2', p2 if os.path.exists(p2) else single)):
        if os.path.exists(path):
            t = load_fdrbench(path, entrap)
            if 'run' in t.columns:
                out[f'{name} run'] = t
            else:
                out[f'{name} exp'] = t
    blib = os.path.join(folder, 'osprey.blib')
    if os.path.exists(blib):
        con = sqlite3.connect(f'file:{blib}?mode=ro', uri=True)
        prot = pd.read_sql_query('SELECT accession AS grp, QValue AS q FROM Proteins', con)
        con.close()
        out['protein'] = prot[~prot['grp'].str.lower().str.startswith('decoy_')]
    return out


def diann_sources(report, entrap):
    df = pd.read_parquet(report, columns=['Run', 'Stripped.Sequence', 'Precursor.Charge', 'Q.Value',
                                          'Global.Q.Value', 'Protein.Group', 'Global.PG.Q.Value'])
    df['key'] = list(zip(df['Stripped.Sequence'], df['Precursor.Charge'].astype(int)))
    df['seq'] = df['Stripped.Sequence']
    exp = df.groupby('key', as_index=False).agg(q=('Global.Q.Value', 'min'), seq=('seq', 'first'))
    run = pd.DataFrame({'key': df['key'], 'seq': df['seq'], 'q': df['Q.Value'], 'run': df['Run'].map(run_label)})
    prot = df.groupby('Protein.Group', as_index=False).agg(q=('Global.PG.Q.Value', 'min'))
    return {'exp': label(exp, entrap), 'run': label(run, entrap), 'protein': prot.rename(columns={'Protein.Group': 'grp'})}


def summarize_table(name, table, r, max_q=None):
    if max_q is not None:
        table = table[table['q'] <= max_q]
    c = curve(table, r)
    n1, fdp1 = at_q(c[:3], NOMINAL)
    i = np.nonzero(c[0] <= NOMINAL)[0]
    lower1 = c[3][i[-1]] if len(i) else np.nan
    row = {'source': name, 'n_q1': n1, 'fdp_q1': fdp1, 'fdp_lower_q1': lower1, 'max_fdp': c[2].max()}
    for lv in LEVELS:
        q_thr, n, _ = at_fdp(c[:3], lv)
        row[f'n_fdp{lv * 100:g}'] = n if lv <= c[2].max() else np.nan
        row[f'q_at_fdp{lv * 100:g}'] = q_thr
    return row, c


def protein_row(name, prot, suffix, r_prot):
    prot = prot.copy()
    prot['entrap'] = prot['grp'].map(lambda g: is_entrapment_group(g, suffix))
    c = curve(prot.dropna(subset=['q']), r_prot)
    n1, fdp1 = at_q(c[:3], NOMINAL)
    return {'source': name, 'n_q1': n1, 'fdp_q1': fdp1}


def trace(diann_exp, arm_sources, r, fdp_level):
    """Each DIA-NN-only precursor at fdp_level, against the Osprey arm: where it was lost."""
    d = summarize_table('d', diann_exp, r)[1]
    d_thr = at_fdp(d[:3], fdp_level)[0]
    p2 = arm_sources['pass2 exp']
    o_curve = summarize_table('o', p2, r, PASS2_FAIR_Q)[1]
    o_thr = at_fdp(o_curve[:3], fdp_level)[0]
    d_ids = set(diann_exp.loc[(diann_exp['q'] <= d_thr) & ~diann_exp['entrap'], 'key'])
    o_ids = set(p2.loc[(p2['q'] <= o_thr) & ~p2['entrap'], 'key'])
    p1 = arm_sources['pass1 exp'].set_index('key')
    p2i = p2.set_index('key')
    rows = []
    for k in sorted(d_ids - o_ids):
        in1, in2 = k in p1.index, k in p2i.index
        q1 = float(p1.at[k, 'q']) if in1 else np.nan
        q2 = float(p2i.at[k, 'q']) if in2 else np.nan
        if not in1:
            where = 'never scored'
        elif not in2:
            where = 'dropped at compaction'
        else:
            where = 'survived, pass-2 q above threshold'
        rows.append({'seq': k[0], 'z': k[1], 'pass1_q': q1, 'pass2_q': q2, 'where': where})
    return pd.DataFrame(rows), d_thr, o_thr, len(d_ids), len(o_ids), len(d_ids & o_ids)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('work_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--suffix', default='_p_target')
    ap.add_argument('--max-q', type=float, default=0.05)
    ap.add_argument('--trace-arm', default='osprey')
    ap.add_argument('--trace-fdp', type=float, default=0.005)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    entrap, r_pep, r_prot = load_space(os.path.join(args.work_dir, 'peptides', 'target_entrapment_peptides.fasta'),
                                       args.suffix)
    sources = {}
    # diann-search is 'DIA-NN' (the trace's reference); other diann-search-<variant> folders are arms.
    for report in sorted(glob.glob(os.path.join(args.work_dir, 'diann-search*', 'report.parquet'))):
        folder = os.path.basename(os.path.dirname(report))
        name = 'DIA-NN' if folder == 'diann-search' else 'DIA-NN ' + folder[len('diann-search-'):]
        sources[name] = diann_sources(report, entrap)
    for path in sorted(glob.glob(os.path.join(args.work_dir, '*', 'FDRBench-Input*.tsv'))):
        folder = os.path.dirname(path)
        name = os.path.basename(folder)
        if name not in sources and not name.startswith('diann'):
            sources[name] = osprey_sources(folder, entrap)

    rows, prows, curves = [], [], {}
    for tool, tabs in sources.items():
        for kind, table in tabs.items():
            if kind == 'protein':
                prows.append(protein_row(tool, table, args.suffix, r_prot))
                continue
            max_q = PASS2_FAIR_Q if kind.startswith('pass2') else None
            if kind.endswith('run') or kind == 'run':
                for run, g in table.groupby('run'):
                    row, _ = summarize_table(f'{tool} {kind} {run}', g, r_pep, max_q)
                    rows.append(row)
                row, c = summarize_table(f'{tool} {kind} (pooled)', table, r_pep, max_q)
            else:
                row, c = summarize_table(f'{tool} {kind}', table, r_pep, max_q)
            rows.append(row)
            curves[f'{tool} {kind}'] = c
    summary = pd.DataFrame(rows)
    proteins = pd.DataFrame(prows)
    summary.to_csv(os.path.join(args.out_dir, 'summary.tsv'), sep='\t', index=False, float_format='%.5g')
    proteins.to_csv(os.path.join(args.out_dir, 'proteins.tsv'), sep='\t', index=False, float_format='%.5g')

    fig, ax = plt.subplots(figsize=(7.5, 6))
    ax.plot([0, args.max_q], [0, args.max_q], color='#999999', lw=0.8, ls=':', label='y = x')
    for i, (name, c) in enumerate(curves.items()):
        keep = c[0] <= args.max_q
        color = f'C{i % 10}'
        ax.plot(c[0][keep], c[2][keep], color=color, lw=1.4, label=name)
        ax.plot(c[0][keep], c[3][keep], color=color, lw=0.9, ls='--')
    ax.set_xlim(0, args.max_q)
    ax.set_ylim(0, args.max_q)
    ax.set_xlabel('reported q-value')
    ax.set_ylabel('entrapment FDP (solid combined, dashed lower bound)')
    ax.set_title(f'Calibration, Astral (r = {r_pep:.3f})')
    ax.legend(fontsize=7, loc='upper left')
    ax.grid(color='#e5e5e5', lw=0.6)
    fig.patch.set_facecolor('white')
    fig.tight_layout()
    fig.savefig(os.path.join(args.out_dir, 'calibration.png'), dpi=150, facecolor='white')

    lines = [f'r (precursor peptides) = {r_pep:.4f}, r (proteins) = {r_prot:.4f}', '',
             summary.to_string(index=False, float_format=lambda v: f'{v:.4g}'), '',
             'Protein groups at reported q <= 1%:', proteins.to_string(index=False, float_format=lambda v: f'{v:.4g}')]
    if 'DIA-NN' in sources and args.trace_arm in sources and 'pass1 exp' in sources[args.trace_arm]:
        tr, d_thr, o_thr, nd, no, both = trace(sources['DIA-NN']['exp'], sources[args.trace_arm], r_pep,
                                               args.trace_fdp)
        tr.to_csv(os.path.join(args.out_dir, 'trace.tsv'), sep='\t', index=False)
        lines += ['', f'Trace at FDP {args.trace_fdp:.2%} ({args.trace_arm}): DIA-NN {nd} (q <= {d_thr:.4g}), '
                      f'Osprey {no} (q <= {o_thr:.4g}), both {both}, DIA-NN only {len(tr)}',
                  tr['where'].value_counts().to_string() if len(tr) else '(none)']
        if len(tr):
            surv = tr[tr['where'].str.startswith('survived')]
            if len(surv):
                lines.append('survived: pass-2 q quantiles ' + ', '.join(
                    f'{p}%={surv["pass2_q"].quantile(p / 100):.3g}' for p in (10, 25, 50, 75, 90)))
            drop = tr[tr['where'] == 'dropped at compaction']
            if len(drop):
                lines.append('dropped: pass-1 q quantiles ' + ', '.join(
                    f'{p}%={drop["pass1_q"].quantile(p / 100):.3g}' for p in (10, 25, 50, 75, 90)))
    text = '\n'.join(lines)
    with open(os.path.join(args.out_dir, 'summary.txt'), 'w') as f:
        f.write(text + '\n')
    print(text)


if __name__ == '__main__':
    main()
