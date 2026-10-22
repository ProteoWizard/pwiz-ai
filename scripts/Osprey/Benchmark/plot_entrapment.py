"""Osprey vs DIA-NN identifications at matched entrapment FDP (Run-DiannEntrapment.ps1 output).

Both tools searched the same target + natural-entrapment peptides. A discovery is entrapment when every
protein of its peptide is an entrapment accession: Osprey names them after the paired target's protein
with FDRBench's _p_target suffix. The FDP of a discovery list is
the combined entrapment estimate (Wen et al. 2025, FDRBench):

    FDP = N_e * (1 + 1/r) / (N_t + N_e)

with r the entrapment-to-target ratio of the searched peptides (precursors) or proteins. Each tool's
q-value threshold is then moved until its estimated FDP equals the chosen level, so the two are
compared at the same error rate rather than at the same nominal q-value.

Levels:
  experiment  precursors over the 3 runs: Osprey's FDRBench export (experiment precursor q), DIA-NN's
              Global.Q.Value
  run         precursors per run: Osprey's RetentionTimes run q (of its reported precursors), DIA-NN's
              Q.Value
  protein     protein groups over the 3 runs: Osprey's Proteins.QValue, DIA-NN's Global.PG.Q.Value

Usage:
  plot_entrapment.py <entrapment dir> <out dir> [--fdp 0.01] [--suffix _ARATH]
writes fdp_curves.png, overlap_experiment.png, overlap_run.png, overlap_protein.png and summary.txt.
"""
import argparse
import os
import re
import sqlite3
import sys

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plot_diann_comparison import draw_upset, run_label, INK, MUTED, GRID  # noqa: E402

DATASETS = ('stellar', 'astral')
OSPREY_COLOR = '#e08a3c'
DIANN_COLOR = '#4a6fb0'


def stripped(seq):
    return re.sub(r'\[[^\]]*\]|\([^)]*\)', '', seq)


# --- the searched space --------------------------------------------------------------------------

def load_space(peptide_fasta, suffix):
    """peptide -> is_entrapment, and the protein-level entrapment ratio, from the peptide FASTA both
    tools searched (one entry per peptide and accession)."""
    proteins = {}
    accession = None
    with open(peptide_fasta) as f:
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                accession = line[1:]
            elif line:
                proteins.setdefault(line, set()).add(accession)
    entrap = {seq: all(a.endswith(suffix) for a in accs) for seq, accs in proteins.items()}
    n_e = sum(entrap.values())
    all_acc = set().union(*proteins.values())
    p_e = sum(1 for a in all_acc if a.endswith(suffix))
    return entrap, n_e / (len(entrap) - n_e), p_e / (len(all_acc) - p_e)


def accessions(group):
    """A protein group's accessions, bare (sp|P55011|S12A2_HUMAN -> P55011), as DIA-NN reports them."""
    out = []
    for a in re.split(r'[;,]', group):
        a = a.strip()
        if a:
            out.append(a.split('|')[1] if a.count('|') >= 2 else a)
    return out


def is_entrapment_group(group, suffix):
    accs = accessions(group)
    return bool(accs) and all(a.endswith(suffix) for a in accs)


# --- FDP curves ------------------------------------------------------------------------------------

def fdp_curve(q, entrapment, r):
    """Sorted by q: for each prefix, (q, targets, FDP). Ties in q are taken together."""
    order = np.argsort(q, kind='stable')
    q, e = np.asarray(q)[order], np.asarray(entrapment, dtype=bool)[order]
    n_e = np.cumsum(e)
    n_t = np.cumsum(~e)
    fdp = n_e * (1 + 1 / r) / np.maximum(n_t + n_e, 1)
    last = np.r_[q[1:] != q[:-1], True]   # only thresholds between distinct q-values
    return q[last], n_t[last], fdp[last]


def at_fdp(curve, level):
    """The largest target count whose FDP stays at or under level (and the q-value it takes)."""
    q, n_t, fdp = curve
    ok = np.nonzero(fdp <= level)[0]
    if len(ok) == 0:
        return np.nan, 0, np.nan
    i = ok[-1]
    return q[i], int(n_t[i]), fdp[i]


def at_q(curve, threshold):
    q, n_t, fdp = curve
    ok = np.nonzero(q <= threshold)[0]
    if len(ok) == 0:
        return 0, np.nan
    return int(n_t[ok[-1]]), fdp[ok[-1]]


# --- the tools' results ----------------------------------------------------------------------------

def osprey_tables(osprey_dir, entrap, suffix):
    fdrbench = pd.read_csv(os.path.join(osprey_dir, 'FDRBench-Input.tsv'), sep='\t')
    exp = pd.DataFrame({'key': list(zip(fdrbench['peptide'], fdrbench['charge'].astype(int))),
                        'q': fdrbench['q_value'].astype(float)})
    exp['seq'] = fdrbench['peptide']
    con = sqlite3.connect(f"file:{os.path.join(osprey_dir, 'osprey.blib')}?mode=ro", uri=True)
    rt = pd.read_sql_query(
        'SELECT s.fileName AS file, r.peptideSeq AS seq, r.precursorCharge AS z, t.score AS q '
        'FROM RetentionTimes t JOIN RefSpectra r ON r.id = t.RefSpectraID '
        'JOIN SpectrumSourceFiles s ON s.id = t.SpectrumSourceID', con)
    prot = pd.read_sql_query('SELECT accession AS grp, QValue AS q FROM Proteins', con)
    con.close()
    rt['run'] = rt['file'].map(run_label)
    rt['key'] = list(zip(rt['seq'], rt['z'].astype(int)))
    prot = prot[~prot['grp'].str.lower().str.startswith('decoy_')]
    return finish(exp, rt, prot, entrap, suffix)


def diann_tables(report, entrap, suffix):
    df = pd.read_parquet(report, columns=['Run', 'Stripped.Sequence', 'Precursor.Charge', 'Q.Value',
                                          'Global.Q.Value', 'Protein.Group', 'Global.PG.Q.Value'])
    df['key'] = list(zip(df['Stripped.Sequence'], df['Precursor.Charge'].astype(int)))
    df['seq'] = df['Stripped.Sequence']
    exp = df.groupby('key', as_index=False).agg(q=('Global.Q.Value', 'min'), seq=('seq', 'first'))
    rt = pd.DataFrame({'run': df['Run'].map(run_label), 'key': df['key'], 'seq': df['seq'], 'q': df['Q.Value']})
    prot = df.groupby('Protein.Group', as_index=False).agg(q=('Global.PG.Q.Value', 'min'))
    prot = prot.rename(columns={'Protein.Group': 'grp'})
    return finish(exp, rt, prot, entrap, suffix)


def finish(exp, rt, prot, entrap, suffix):
    for t in (exp, rt):
        t['entrap'] = t['seq'].map(lambda s: entrap.get(stripped(s), False))
    prot['entrap'] = prot['grp'].map(lambda g: is_entrapment_group(g, suffix))
    return {'experiment': exp, 'run': rt, 'protein': prot}


# --- analysis ----------------------------------------------------------------------------------------

def analyze(edir, suffix, level):
    entrap, r_pep, r_prot = load_space(os.path.join(edir, 'peptides', 'target_entrapment_peptides.fasta'), suffix)
    tools = {'Osprey': osprey_tables(os.path.join(edir, 'osprey'), entrap, suffix),
             'DIA-NN': diann_tables(os.path.join(edir, 'diann-search', 'report.parquet'), entrap, suffix)}
    res = {'r_pep': r_pep, 'r_prot': r_prot, 'tools': {}}
    for tool, tables in tools.items():
        out = {}
        exp = tables['experiment']
        out['experiment'] = curve_info(exp, r_pep, level)
        out['run'] = {run: curve_info(g, r_pep, level) for run, g in tables['run'].groupby('run')}
        out['protein'] = curve_info(tables['protein'], r_prot, level, key='grp')
        res['tools'][tool] = out
    return res


def curve_info(table, r, level, key='key'):
    table = table.dropna(subset=['q'])
    curve = fdp_curve(table['q'].values, table['entrap'].values, r)
    q_thr, n, fdp = at_fdp(curve, level)
    n_nominal, fdp_nominal = at_q(curve, level)
    chosen = table[(table['q'] <= q_thr) & ~table['entrap']][key] if not np.isnan(q_thr) else []
    ids = set()
    for k in chosen:
        if key == 'grp':
            ids.update(accessions(k))   # accessions, so the two tools' groupings compare
        else:
            ids.add(k)
    return {'curve': curve, 'q': q_thr, 'n': n, 'fdp': fdp, 'n_nominal': n_nominal,
            'fdp_nominal': fdp_nominal, 'ids': ids}


# --- plots -------------------------------------------------------------------------------------------

def style(ax):
    for side in ('top', 'right'):
        ax.spines[side].set_visible(False)
    ax.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(colors=MUTED, labelsize=8.5)


def plot_curves(results, level, out_png):
    cols = [('experiment', 'Precursors, experiment level'), ('run', 'Precursors per run'),
            ('protein', 'Protein groups, experiment level')]
    fig, axes = plt.subplots(len(results), 3, figsize=(14, 4 * len(results)), facecolor='white', squeeze=False)
    for row, (dataset, res) in zip(axes, results.items()):
        for ax, (lvl, title) in zip(row, cols):
            style(ax)
            for tool, color in (('DIA-NN', DIANN_COLOR), ('Osprey', OSPREY_COLOR)):
                info = res['tools'][tool][lvl]
                infos = info.values() if lvl == 'run' else [info]
                for k, inf in enumerate(infos):
                    q, n_t, fdp = inf['curve']
                    keep = fdp <= 0.05
                    ax.plot(fdp[keep] * 100, n_t[keep], color=color, linewidth=1.6,
                            label=tool if k == 0 else None, alpha=0.9)
                    ax.plot([inf['fdp_nominal'] * 100], [inf['n_nominal']], marker='o', color=color,
                            markersize=5, markerfacecolor='white', zorder=4)
            ax.axvline(level * 100, color=INK, linestyle='--', linewidth=0.9)
            ax.set_xlim(0, 3)
            ax.set_xlabel('Entrapment-estimated FDP (%)', fontsize=9, color=MUTED)
            ax.set_ylabel('Target IDs', fontsize=9, color=MUTED)
            ax.set_title(f'{dataset.capitalize()}: {title}', fontsize=10.5, color=INK, loc='left')
        row[0].legend(frameon=False, fontsize=9, loc='lower right')
    fig.text(0.01, 0.005, 'Open circles: each tool at its own q <= 1% (the FDP it actually delivers there). '
             'Dashed line: the matched FDP the overlaps use.', fontsize=8.5, color=MUTED)
    fig.tight_layout(rect=(0, 0.02, 1, 1))
    fig.savefig(out_png, dpi=200, facecolor='white')


def plot_overlaps(results, level, lvl, out_png, title):
    panels = []
    for dataset, res in results.items():
        sets = {}
        for tool in ('DIA-NN', 'Osprey'):
            info = res['tools'][tool][lvl]
            if lvl == 'run':
                for run, inf in sorted(info.items()):
                    sets[f'{tool} {run}'] = inf['ids']
            else:
                sets[tool] = info['ids']
        panels.append((dataset, sets))
    fig = plt.figure(figsize=(9 * len(panels), 6 if lvl == 'run' else 4.5), facecolor='white')
    areas = fig.subfigures(1, len(panels), squeeze=False)[0]
    for area, (dataset, sets) in zip(areas, panels):
        draw_upset(area, sets, f'{dataset.capitalize()} - {title} at {level * 100:g}% entrapment FDP')
    fig.savefig(out_png, dpi=200, facecolor='white', bbox_inches='tight')


def summarize(results, level):
    lines = []
    for dataset, res in results.items():
        lines.append(f'{dataset}: r (precursors) = {res["r_pep"]:.4f}, r (proteins) = {res["r_prot"]:.4f}')
        for tool, out in res['tools'].items():
            for lvl in ('experiment', 'protein'):
                inf = out[lvl]
                lines.append(f'  {tool:7s} {lvl:10s} q<=1%: {inf["n_nominal"]:7d} at FDP {inf["fdp_nominal"] * 100:5.2f}% | '
                             f'at FDP {level * 100:g}%: {inf["n"]:7d} (q {inf["q"]:.4f})')
            for run, inf in sorted(out['run'].items()):
                lines.append(f'  {tool:7s} run {run:6s} q<=1%: {inf["n_nominal"]:7d} at FDP {inf["fdp_nominal"] * 100:5.2f}% | '
                             f'at FDP {level * 100:g}%: {inf["n"]:7d} (q {inf["q"]:.4f})')
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('entrapment_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--fdp', type=float, default=0.01)
    ap.add_argument('--suffix', default='_p_target')
    a = ap.parse_args()
    results = {}
    for dataset in DATASETS:
        edir = os.path.join(a.entrapment_dir, dataset)
        if os.path.exists(os.path.join(edir, 'diann-search', 'report.parquet')) and \
                os.path.exists(os.path.join(edir, 'osprey', 'FDRBench-Input.tsv')):
            results[dataset] = analyze(edir, a.suffix, a.fdp)
    if not results:
        sys.exit(f'No complete datasets under {a.entrapment_dir}')
    os.makedirs(a.out_dir, exist_ok=True)
    text = summarize(results, a.fdp)
    print(text)
    with open(os.path.join(a.out_dir, 'summary.txt'), 'w') as f:
        f.write(text + '\n')
    plot_curves(results, a.fdp, os.path.join(a.out_dir, 'fdp_curves.png'))
    plot_overlaps(results, a.fdp, 'experiment', os.path.join(a.out_dir, 'overlap_experiment.png'),
                  'precursors, experiment level')
    plot_overlaps(results, a.fdp, 'run', os.path.join(a.out_dir, 'overlap_run.png'), 'precursors per run')
    plot_overlaps(results, a.fdp, 'protein', os.path.join(a.out_dir, 'overlap_protein.png'),
                  'protein accessions in passing groups')
    print(f'Wrote figures to {a.out_dir}')


if __name__ == '__main__':
    main()
