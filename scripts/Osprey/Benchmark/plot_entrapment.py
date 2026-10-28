"""Osprey vs DIA-NN identifications at matched entrapment FDP (Run-DiannEntrapment.ps1 output).

Both tools searched the same target + natural-entrapment peptides. A discovery is entrapment when every
protein of its peptide is an entrapment accession: Osprey names them after the paired target's protein
with FDRBench's _p_target suffix. The FDP of a discovery list is the combined entrapment estimate
(Wen et al. 2025, FDRBench):

    FDP = N_e * (1 + 1/r) / (N_t + N_e)

with r the entrapment-to-target ratio of the searched peptides (precursors) or protein accessions.

Levels, and what each can support:
  experiment  precursors over the 3 runs: Osprey's FDRBench export (experiment precursor q, a fair
              sample of its candidates up to q 0.015, --osprey-max-q), DIA-NN's Global.Q.Value. Each
              tool's q threshold is moved until its FDP equals the matched level - the highest FDP both
              curves reach, at most 1% - so the two are compared at the same error rate.
  run         precursors per run at q <= 1%, labeled with the FDP each delivers: Osprey reports run q
              only for precursors that passed the experiment level, so its run curve stops early.
  protein     protein groups at q <= 1%, labeled with their FDP: in this Osprey build every group
              reports q = 0 (fixed by pwiz #4823), so its groups cannot be moved to a matched FDP.

Usage:
  plot_entrapment.py <entrapment dir> <out dir> [--suffix _p_target] [--osprey-max-q 0.015]
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
# Arms: DIA-NN, then each Osprey search folder that exists (label -> folder under the dataset dir).
OSPREY_ARMS = (('Osprey', 'osprey'), ('Osprey gbdt', 'osprey-gbdt'))
COLORS = {'DIA-NN': '#4a6fb0', 'Osprey': '#e08a3c', 'Osprey gbdt': '#2b8a6c'}
NOMINAL = 0.01
TABLE_LEVELS = (0.002, 0.003, 0.004, 0.005, 0.0075, 0.01)


def stripped(seq):
    return re.sub(r'\[[^\]]*\]|\([^)]*\)', '', seq)


# --- the searched space --------------------------------------------------------------------------

def load_space(peptide_fasta, suffix):
    """peptide -> is_entrapment, and the precursor and protein entrapment ratios, from the peptide FASTA
    both tools searched (one entry per peptide and accession)."""
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
    # Per run, only precursors that pass the experiment level, as Osprey reports run q-values only for them.
    passing = df['Global.Q.Value'] <= NOMINAL
    rt = pd.DataFrame({'run': df.loc[passing, 'Run'].map(run_label), 'key': df.loc[passing, 'key'],
                       'seq': df.loc[passing, 'seq'], 'q': df.loc[passing, 'Q.Value']})
    prot = df.groupby('Protein.Group', as_index=False).agg(q=('Global.PG.Q.Value', 'min'))
    prot = prot.rename(columns={'Protein.Group': 'grp'})
    return finish(exp, rt, prot, entrap, suffix)


def finish(exp, rt, prot, entrap, suffix):
    for t in (exp, rt):
        t['entrap'] = t['seq'].map(lambda s: entrap.get(stripped(s), False))
    prot['entrap'] = prot['grp'].map(lambda g: is_entrapment_group(g, suffix))
    return {'experiment': exp, 'run': rt, 'protein': prot}


# --- analysis ----------------------------------------------------------------------------------------

def analyze(edir, suffix, osprey_max_q):
    entrap, r_pep, r_prot = load_space(os.path.join(edir, 'peptides', 'target_entrapment_peptides.fasta'), suffix)
    tools = {'DIA-NN': diann_tables(os.path.join(edir, 'diann-search', 'report.parquet'), entrap, suffix)}
    for label, folder in OSPREY_ARMS:
        if os.path.exists(os.path.join(edir, folder, 'FDRBench-Input.tsv')):
            tools[label] = osprey_tables(os.path.join(edir, folder), entrap, suffix)
            # Osprey's FDRBench export samples its candidates fairly only up to about q 0.015: past that
            # the pass-1 compaction has already dropped most entrapment, so its FDP curve flattens falsely.
            exp = tools[label]['experiment']
            tools[label]['experiment'] = exp[exp['q'] <= osprey_max_q]
    res = {'r_pep': r_pep, 'r_prot': r_prot, 'tools': {}}
    for tool, tables in tools.items():
        res['tools'][tool] = {
            'experiment': curve_info(tables['experiment'], r_pep),
            'run': {run: curve_info(g, r_pep) for run, g in tables['run'].groupby('run')},
            'protein': curve_info(tables['protein'], r_prot, key='grp'),
        }
    # The matched level: the highest FDP both experiment-level curves reach, rounded down to 0.05%.
    reach = min(res['tools'][t]['experiment']['curve'][2].max() for t in tools)
    res['matched'] = min(NOMINAL, np.floor(reach * 2000) / 2000)
    for tool in tools:
        inf = res['tools'][tool]['experiment']
        inf['matched'] = select(inf, res['matched'])
        inf['levels'] = {lv: at_fdp(inf['curve'], lv) for lv in TABLE_LEVELS if lv <= reach}
    return res


def curve_info(table, r, key='key'):
    table = table.dropna(subset=['q'])
    curve = fdp_curve(table['q'].values, table['entrap'].values, r)
    n, fdp = at_q(curve, NOMINAL)
    return {'curve': curve, 'table': table, 'key': key,
            'nominal': {'q': NOMINAL, 'n': n, 'fdp': fdp, 'ids': ids_at(table, NOMINAL, key)}}


def select(info, level):
    q_thr, n, fdp = at_fdp(info['curve'], level)
    return {'q': q_thr, 'n': n, 'fdp': fdp, 'ids': ids_at(info['table'], q_thr, info['key'])}


def ids_at(table, q_thr, key):
    ids = set()
    if np.isnan(q_thr):
        return ids
    for k in table[(table['q'] <= q_thr) & ~table['entrap']][key]:
        if key == 'grp':
            ids.update(accessions(k))   # accessions, so the two tools' groupings compare
        else:
            ids.add(k)
    return ids


# --- plots -------------------------------------------------------------------------------------------

def style(ax):
    for side in ('top', 'right'):
        ax.spines[side].set_visible(False)
    ax.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(colors=MUTED, labelsize=8.5)


def plot_curves(results, out_png):
    cols = [('experiment', 'Precursors, experiment level'), ('run', 'Precursors per run'),
            ('protein', 'Protein groups')]
    fig, axes = plt.subplots(len(results), 3, figsize=(14, 4 * len(results)), facecolor='white', squeeze=False)
    for row, (dataset, res) in zip(axes, results.items()):
        for ax, (lvl, title) in zip(row, cols):
            style(ax)
            xmax = 0.0
            for tool, color in ((t, COLORS[t]) for t in res['tools']):
                info = res['tools'][tool][lvl]
                infos = info.values() if lvl == 'run' else [info]
                for k, inf in enumerate(infos):
                    q, n_t, fdp = inf['curve']
                    # Past q 5%, and below 30% of the curve's count, where a few IDs swing the FDP.
                    keep = (q <= 0.05) & (n_t >= 0.3 * n_t.max())
                    ax.plot(fdp[keep] * 100, n_t[keep], color=color, linewidth=1.6, alpha=0.9,
                            label=tool if k == 0 else None, marker='o' if keep.sum() == 1 else None)
                    nom = inf['nominal']
                    ax.plot([nom['fdp'] * 100], [nom['n']], marker='o', color=color, markersize=6,
                            markerfacecolor='white', markeredgewidth=1.6, zorder=4)
                    xmax = max(xmax, nom['fdp'] * 100)
            if lvl == 'experiment':
                ax.axvline(res['matched'] * 100, color=INK, linestyle='--', linewidth=0.9)
            ax.set_xlim(0, max(1.2, xmax * 1.15))
            ax.set_xlabel('Entrapment-estimated FDP (%)', fontsize=9, color=MUTED)
            ax.set_ylabel('Target IDs', fontsize=9, color=MUTED)
            ax.set_title(f'{dataset.capitalize()}: {title}', fontsize=10.5, color=INK, loc='left')
        row[0].legend(frameon=False, fontsize=9, loc='lower right')
    fig.text(0.01, 0.005, 'Open circles: each tool at its own q <= 1%, placed at the FDP it actually delivers. '
             'Dashed line: the matched FDP of the experiment-level overlap.\nOsprey reports run q-values only '
             'for precursors that passed the experiment level, so its run curves stop early; its protein '
             'groups all report q = 0 in this build (pwiz #4823), so they are one point.',
             fontsize=8.5, color=MUTED)
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    fig.savefig(out_png, dpi=200, facecolor='white')


def plot_overlaps(results, lvl, out_png):
    panels = []
    for dataset, res in results.items():
        sets = {}
        for tool in res['tools']:
            info = res['tools'][tool][lvl]
            if lvl == 'run':
                for run, inf in sorted(info.items()):
                    sets[f"{tool} {run} ({inf['nominal']['fdp'] * 100:.2f}%)"] = inf['nominal']['ids']
            elif lvl == 'experiment':
                sets[f"{tool} (q {info['matched']['q']:.4f})"] = info['matched']['ids']
            else:
                sets[f"{tool} ({info['nominal']['fdp'] * 100:.2f}%)"] = info['nominal']['ids']
        name = dataset.capitalize()
        if lvl == 'experiment':
            title = f'{name} - precursors, experiment level, at matched {res["matched"] * 100:g}% FDP'
        elif lvl == 'run':
            title = f'{name} - precursors per run at q <= 1% (estimated FDP)'
        else:
            title = f'{name} - protein accessions in groups at q <= 1% (estimated FDP)'
        panels.append((title, sets))
    fig = plt.figure(figsize=(9.5 * len(panels), 6 if lvl == 'run' else 4.5), facecolor='white')
    areas = fig.subfigures(1, len(panels), squeeze=False)[0]
    for area, (title, sets) in zip(areas, panels):
        draw_upset(area, sets, title, ylabel='Protein accessions' if lvl == 'protein' else 'Precursors')
    fig.savefig(out_png, dpi=200, facecolor='white', bbox_inches='tight')


def summarize(results):
    lines = []
    for dataset, res in results.items():
        lines.append(f'{dataset}: r (precursors) = {res["r_pep"]:.4f}, r (protein accessions) = {res["r_prot"]:.4f}; '
                     f'matched experiment FDP {res["matched"] * 100:g}%')
        for tool, out in res['tools'].items():
            e = out['experiment']
            lines.append(f'  {tool:7s} experiment  q<=1%: {e["nominal"]["n"]:7d} at FDP {e["nominal"]["fdp"] * 100:5.2f}% | '
                         f'matched: {e["matched"]["n"]:7d} (q {e["matched"]["q"]:.4f})')
            lines.append('  ' + ' ' * 20 + ' | '.join(f'FDP {lv * 100:g}%: {v[1]}' for lv, v in e['levels'].items()))
            p = out['protein']['nominal']
            lines.append(f'  {tool:7s} protein     q<=1%: {p["n"]:7d} groups at FDP {p["fdp"] * 100:5.2f}%')
            for run, inf in sorted(out['run'].items()):
                n = inf['nominal']
                lines.append(f'  {tool:7s} run {run:7s} q<=1%: {n["n"]:7d} at FDP {n["fdp"] * 100:5.2f}%')
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('entrapment_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--suffix', default='_p_target')
    ap.add_argument('--osprey-max-q', type=float, default=0.015,
                    help="the last q-value at which Osprey's FDRBench export samples its candidates fairly")
    a = ap.parse_args()
    results = {}
    for dataset in DATASETS:
        edir = os.path.join(a.entrapment_dir, dataset)
        if os.path.exists(os.path.join(edir, 'diann-search', 'report.parquet')) and \
                os.path.exists(os.path.join(edir, 'osprey', 'FDRBench-Input.tsv')):
            results[dataset] = analyze(edir, a.suffix, a.osprey_max_q)
    if not results:
        sys.exit(f'No complete datasets under {a.entrapment_dir}')
    os.makedirs(a.out_dir, exist_ok=True)
    text = summarize(results)
    print(text)
    with open(os.path.join(a.out_dir, 'summary.txt'), 'w') as f:
        f.write(text + '\n')
    plot_curves(results, os.path.join(a.out_dir, 'fdp_curves.png'))
    plot_overlaps(results, 'experiment', os.path.join(a.out_dir, 'overlap_experiment.png'))
    plot_overlaps(results, 'run', os.path.join(a.out_dir, 'overlap_run.png'))
    plot_overlaps(results, 'protein', os.path.join(a.out_dir, 'overlap_protein.png'))
    print(f'Wrote figures to {a.out_dir}')


if __name__ == '__main__':
    main()
