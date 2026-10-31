r"""Osprey vs DIA-NN precursor-level comparison as one interactive HTML page.

The question the page answers first: which precursors does one tool call with very high confidence
while the other gives its best peak for the same precursor a low one (or does not report it), and are
the two tools looking at the same chromatographic peak when they disagree?

Inputs, from a Run-DiannComparison.ps1 work folder plus three untimed passes, each the command in a
step's command.txt with changes:
  osprey-export-run\FDRBench-Input.pass{1,2}.tsv         osprey-search with --output-dir/-o/--log-file here,
                                                         + --fdrbench <this>\FDRBench-Input.tsv
                                                         --fdrbench-pass both --fdrbench-per-run
  osprey-export-run\<run>.scores[-reconciled].parquet    written by that pass: Osprey's peak per run
  osprey-export-experiment\FDRBench-Input.pass{1,2}.tsv  the same without --fdrbench-per-run
  diann-search-loose\report.parquet                      diann-search with --qvalue 0.5 and paths here
Requires pandas, pyarrow and plotly (pip install --user), whose plotly.min.js is inlined into the page.

Pass 2 holds the compaction survivors with the q Osprey reports; pass 1 every precursor the first pass
scored. A precursor's Osprey q is its pass-2 q when it survived compaction, else its pass-1 q (and it is
marked 'dropped at compaction').

An ID at 1% means run q <= 0.01 and experiment q <= 0.01, for both tools (DIA-NN: Q.Value and
Global.Q.Value). Precursors are matched on the modified sequence with modifications written as UniMod
ids, and the charge. Peaks match by the rules of Skyline's Compare Peak Picking
(Model/ComparePeakBoundaries.cs): either apex inside the other's boundaries, or the overlap at least
half the mean width.

Usage:
  compare_osprey_diann.py <work dir> <out.html> [--confident 0.001] [--weak 0.05] [--max-rows 4000]
"""
import argparse
import glob
import html
import json
import os
import re
import sys

import numpy as np
import pandas as pd
import pyarrow.compute as pc
import pyarrow.parquet as pq

UNIMOD_BY_MASS = {'57.02': 'UniMod:4', '15.99': 'UniMod:35', '42.01': 'UniMod:1', '79.97': 'UniMod:21'}
NOMINAL = 0.01
Q_FLOOR = 1e-6
MISSING = 'not reported'


def unimod(modseq):
    """Osprey's C[+57.0215] as DIA-NN's C(UniMod:4)."""
    def repl(m):
        mass = '%.2f' % abs(float(m.group(1)))
        return '(%s)' % UNIMOD_BY_MASS.get(mass, m.group(1))
    return re.sub(r'\[([+-]?[\d.]+)\]', repl, modseq)


def run_name(path):
    return os.path.splitext(os.path.basename(str(path).replace('\\', '/')))[0]


def read_fdrbench(folder, per_run):
    """key[, run] -> q, score, pass ('2' survivor or '1' dropped at compaction)."""
    frames = []
    for n in ('1', '2'):
        path = os.path.join(folder, f'FDRBench-Input.pass{n}.tsv')
        cols = ['mod_peptide', 'charge', 'q_value', 'score', 'protein'] + (['run'] if per_run else [])
        df = pd.read_csv(path, sep='\t', usecols=cols)
        df['pass'] = n
        frames.append(df)
    df = pd.concat(frames)
    df['key'] = df['mod_peptide'].map(unimod) + '/' + df['charge'].astype(str)
    if per_run:
        df['run'] = df['run'].map(run_name)
    keys = ['key', 'run'] if per_run else ['key']
    # Pass 2 wins where the precursor survived compaction.
    df = df.sort_values('pass').drop_duplicates(keys, keep='last')
    return df.set_index(keys)


def read_osprey_peaks(folder):
    """(key, run) -> apex, start, end: the reconciled (second-pass) peak where there is one, else the first."""
    frames = []
    for path in sorted(glob.glob(os.path.join(folder, '*.scores.parquet'))):
        for p, rank in ((path.replace('.scores.parquet', '.scores-reconciled.parquet'), 0), (path, 1)):
            if not os.path.exists(p):
                continue
            t = pq.read_table(p, columns=['is_decoy', 'modified_sequence', 'charge', 'apex_rt', 'start_rt',
                                          'end_rt', 'bounds_area', 'file_name'])
            t = t.filter(pc.invert(t.column('is_decoy')))
            df = t.drop(['is_decoy']).to_pandas()
            df['rank'] = rank
            frames.append(df)
    df = pd.concat(frames)
    df['key'] = df['modified_sequence'].map(unimod) + '/' + df['charge'].astype(str)
    df['run'] = df['file_name'].map(run_name)
    df = df.sort_values('rank').drop_duplicates(['key', 'run'], keep='first')
    return df.set_index(['key', 'run'])[['apex_rt', 'start_rt', 'end_rt', 'bounds_area']]


def read_diann(path):
    t = pq.read_table(path, columns=['Run', 'Modified.Sequence', 'Precursor.Charge', 'Decoy', 'Q.Value',
                                     'Global.Q.Value', 'PEP', 'RT', 'RT.Start', 'RT.Stop', 'Predicted.RT',
                                     'Protein.Group', 'Precursor.Quantity'])
    df = t.to_pandas()
    df = df[df['Decoy'] == 0]
    df['key'] = df['Modified.Sequence'] + '/' + df['Precursor.Charge'].astype(str)
    df['run'] = df['Run'].map(run_name)
    return df.drop_duplicates(['key', 'run']).set_index(['key', 'run'])


def peaks_match(a_apex, a_start, a_end, b_apex, b_start, b_end):
    inside = ((b_start <= a_apex) & (a_apex <= b_end)) | ((a_start <= b_apex) & (b_apex <= a_end))
    overlap = np.minimum(a_end, b_end) - np.maximum(a_start, b_start)
    mean_width = ((a_end - a_start) + (b_end - b_start)) / 2
    return inside | (overlap >= 0.5 * mean_width)


def q_bin(q, dropped=None):
    out = np.full(len(q), MISSING, dtype=object)
    edges = [(0, 0.001, 'q <= 0.1%'), (0.001, 0.01, '0.1-1%'), (0.01, 0.05, '1-5%'), (0.05, 0.2, '5-20%'),
             (0.2, 1.01, '> 20%')]
    for lo, hi, name in edges:
        out[(q > lo if lo else q >= 0) & (q <= hi)] = name
    if dropped is not None:
        out[dropped & ~np.isnan(q)] = out[dropped & ~np.isnan(q)] + ' (dropped at compaction)'
    return out


def build(work, args):
    run_export = os.path.join(work, args.osprey_run)
    o_run = read_fdrbench(run_export, per_run=True)
    o_exp = read_fdrbench(os.path.join(work, args.osprey_experiment), per_run=False)
    peaks = read_osprey_peaks(run_export)
    dn = read_diann(os.path.join(work, args.diann, 'report.parquet'))

    o = o_run.join(peaks, how='left')
    o['exp_q'] = o_exp['q_value'].reindex(o.index.get_level_values('key')).values
    df = o.join(dn, how='outer')
    df['run'] = df.index.get_level_values('run')
    df['key'] = df.index.get_level_values('key')
    df = df.reset_index(drop=True)

    oq = df['q_value'].astype(float).values
    oe = df['exp_q'].astype(float).values
    dq = df['Q.Value'].astype(float).values
    dg = df['Global.Q.Value'].astype(float).values
    o_id = (oq <= NOMINAL) & (oe <= NOMINAL)
    d_id = (dq <= NOMINAL) & (dg <= NOMINAL)
    df['status'] = np.select([o_id & d_id, o_id, d_id], ['both', 'Osprey only', 'DIA-NN only'], 'neither')
    match = peaks_match(df['apex_rt'].values, df['start_rt'].values, df['end_rt'].values,
                        df['RT'].values, df['RT.Start'].values, df['RT.Stop'].values)
    both_peaks = ~np.isnan(df['apex_rt'].values) & ~np.isnan(df['RT'].values)
    df['peak'] = np.where(both_peaks, np.where(match, 'same peak', 'different peak'), 'one tool only')
    df['dropped'] = (df['pass'] == '1').values
    df['osprey_bin'] = q_bin(oq, df['dropped'].values)
    df['diann_bin'] = q_bin(dq)
    df['rt'] = df['RT'].astype(float).fillna(df['apex_rt'].astype(float))
    df['protein'] = df['protein'].fillna(df['Protein.Group'])
    df['o_id'], df['d_id'] = o_id, d_id
    # From each tool's side, what became of its 1% IDs in the other tool.
    agree = o_id & d_id & (df['peak'].values == 'same peak')
    diff = df['peak'].values == 'different peak'
    for tool, mine, other in (('osprey', o_id, d_id), ('diann', d_id, o_id)):
        df[f'{tool}_fate'] = np.select(
            [~mine, agree, diff, df['peak'].values == 'same peak'],
            ['', 'agree: same peak at 1%', 'different peak', 'same peak, other tool above 1%'],
            'other tool reports no peak')
    return df


ROC_MAX_Q = 0.5   # the loose DIA-NN report stops here, so both curves do
FATES = ['agree: same peak at 1%', 'same peak, other tool above 1%', 'different peak', 'other tool reports no peak']


def fate_histogram(values, fates, edges):
    """Counts per fate in each bin, and the disagreement fraction per bin."""
    out = {}
    idx = np.clip(np.digitize(values, edges) - 1, 0, len(edges) - 2)
    ok = ~np.isnan(values)
    for f in FATES:
        sel = ok & (fates == f)
        out[f] = np.bincount(idx[sel], minlength=len(edges) - 1).tolist()
    total = np.array([sum(out[f][i] for f in FATES) for i in range(len(edges) - 1)])
    agree = np.array(out[FATES[0]])
    out['disagree_fraction'] = [round(float(1 - a / t), 4) if t >= 20 else None for a, t in zip(agree, total)]
    return out


def roc(df, truth_tool, ranked_tool):
    """ranked_tool's scored precursor-runs in score order against truth_tool's 1% IDs as ground truth: a call
    is a true positive when the precursor is a truth ID and the two peaks match, else a false positive."""
    truth = df[f'{truth_tool}_fate'].values != ''
    if ranked_tool == 'osprey':
        q, tie = df['q_value'].astype(float).values, -df['score'].astype(float).values
    else:
        q, tie = df['Q.Value'].astype(float).values, df['PEP'].astype(float).values
    scored = ~np.isnan(q) & (q <= ROC_MAX_Q)
    order = np.lexsort((tie[scored], q[scored]))
    qs = q[scored][order]
    tp = (truth & (df['peak'].values == 'same peak'))[scored][order]
    ctp, cfp = np.cumsum(tp), np.cumsum(~tp)
    n_truth = int(truth.sum())
    keep = np.unique(np.linspace(0, len(qs) - 1, 1500).astype(int))
    at = int(np.searchsorted(qs, NOMINAL, side='right')) - 1
    return {'fp': cfp[keep].tolist(), 'tpr': (ctp[keep] / n_truth).round(5).tolist(), 'q': qs[keep].round(5).tolist(),
            'n_truth': n_truth, 'at_1pct': {'fp': int(cfp[at]), 'tpr': round(float(ctp[at] / n_truth), 5)} if at >= 0 else None,
            'max_tpr': round(float(ctp[-1] / n_truth), 5)}


def payload(df, args):
    runs = sorted(df['run'].unique())
    out = {'runs': runs, 'confident': args.confident, 'weak': args.weak}

    out['per_run'] = {s: [int(((df['run'] == r) & (df['status'] == s)).sum()) for r in runs]
                      for s in ('both', 'Osprey only', 'DIA-NN only')}
    exp = df[df['status'] != 'neither'].groupby('key')['status'].agg(set)
    out['experiment'] = {
        'osprey': int(df.loc[df['status'].isin(['both', 'Osprey only']), 'key'].nunique()),
        'diann': int(df.loc[df['status'].isin(['both', 'DIA-NN only']), 'key'].nunique()),
        'union': int(len(exp)),
    }
    # Where each tool put the other's IDs.
    def where(sub, col):
        vc = sub[col].value_counts()
        return {k: int(v) for k, v in vc.items()}
    out['diann_only_in_osprey'] = where(df[df['status'] == 'DIA-NN only'], 'osprey_bin')
    out['osprey_only_in_diann'] = where(df[df['status'] == 'Osprey only'], 'diann_bin')
    out['peak_by_status'] = {s: where(df[df['status'] == s], 'peak') for s in ('both', 'Osprey only', 'DIA-NN only')}

    # RT-binned IDs (1 min bins on DIA-NN's RT, else Osprey's apex).
    ids = df[df['status'] != 'neither']
    bins = np.floor(ids['rt'].values).astype(int)
    lo, hi = int(bins.min()), int(bins.max())
    out['rt_bins'] = list(range(lo, hi + 1))
    out['rt_hist'] = {s: np.bincount(bins[ids['status'].values == s] - lo, minlength=hi - lo + 1).tolist()
                      for s in ('both', 'Osprey only', 'DIA-NN only')}

    # RT agreement where both tools have a peak, sampled.
    both = df[(df['peak'] != 'one tool only') & (df['status'] != 'neither')]
    # Osprey apex on DIA-NN RT: a line fit to the same-peak pairs, so the residuals show trends and spread
    # along the gradient, and the different-peak pairs stand out as far from it.
    same = both[both['peak'] == 'same peak']
    slope, intercept = np.polyfit(same['RT'].astype(float), same['apex_rt'].astype(float), 1)
    resid_all = both['apex_rt'].astype(float) - (slope * both['RT'].astype(float) + intercept)
    same_resid = resid_all[both['peak'] == 'same peak']
    out['rt_fit'] = {'slope': float(slope), 'intercept': float(intercept), 'n': int(len(same)),
                     'sd': float(same_resid.std()), 'mad': float(1.4826 * (same_resid - same_resid.median()).abs().median())}
    sample = both.sample(min(len(both), 30000), random_state=1)
    out['rt_scatter'] = {
        'x': sample['RT'].round(3).tolist(), 'y': sample['apex_rt'].round(3).tolist(),
        'resid': resid_all.loc[sample.index].round(4).tolist(),
        'status': sample['status'].tolist(), 'peak': sample['peak'].tolist(),
    }
    # Apex delta histograms over every pair, not the sample: Osprey apex - DIA-NN RT, in seconds.
    delta = (both['apex_rt'].astype(float) - both['RT'].astype(float)).values * 60
    edges = np.arange(-60, 60.5, 1.0)
    out['delta_edges'] = edges.tolist()
    out['delta_hist'] = {}
    for p in ('same peak', 'different peak'):
        d = delta[(both['peak'] == p).values]
        out['delta_hist'][p] = {'counts': np.histogram(np.clip(d, -60, 60), edges)[0].tolist(),
                                'n': int(len(d)), 'median': float(np.median(d)) if len(d) else 0.0,
                                'beyond': int((np.abs(d) > 60).sum())}

    # Score-vs-score: -log10 run q, split by whether the two peaks match; missing placed below the axis.
    def lq(q):
        return np.where(np.isnan(q), -0.6, -np.log10(np.clip(q, Q_FLOOR, 1)))
    scored = df[df['status'] != 'neither']
    edges = np.linspace(-0.8, 6.2, 71)
    out['heat'] = {'edges': edges.round(2).tolist()}
    for p in ('same peak', 'different peak', 'one tool only'):
        # Same peak: every pair where both tools chose it, at any q, to show where the 1% cut splits them.
        sub = df[(df['peak'] == p).values] if p == 'same peak' else scored[(scored['peak'] == p).values]
        oq = sub['q_value'].astype(float).values
        dq = sub['Q.Value'].astype(float).values
        h, _, _ = np.histogram2d(lq(oq), lq(dq), bins=[edges, edges])
        o1, d1 = oq <= NOMINAL, dq <= NOMINAL
        both_q = ~np.isnan(oq) & ~np.isnan(dq)
        # Spearman: Pearson on average ranks (no scipy dependency).
        rho = pd.Series(oq[both_q]).rank().corr(pd.Series(dq[both_q]).rank()) if both_q.sum() > 2 else None
        out['heat'][p] = {'z': np.log10(h.T + 1).round(3).tolist(), 'n': h.T.astype(int).tolist(), 'total': int(len(sub)),
                          'quad': {'both': int((o1 & d1).sum()), 'osprey': int((o1 & ~d1).sum()),
                                   'diann': int((~o1 & d1).sum()), 'neither': int((~o1 & ~d1).sum())},
                          'rho': None if rho is None or np.isnan(rho) else round(float(rho), 3)}

    # Disagreements: confident in one tool, weak or missing in the other.
    oq = df['q_value'].astype(float)
    dq = df['Q.Value'].astype(float)
    sets = {
        'diann': df[(dq <= args.confident) & (oq.isna() | (oq > args.weak))].sort_values('Q.Value'),
        'osprey': df[(oq <= args.confident) & (dq.isna() | (dq > args.weak))].sort_values('q_value'),
    }
    out['disagree_counts'] = {k: int(len(v)) for k, v in sets.items()}
    out['disagree_peak'] = {k: where(v, 'peak') for k, v in sets.items()}
    out['disagree_rt'] = {k: v['rt'].round(2).tolist() for k, v in sets.items()}
    cols = ['run', 'key', 'protein', 'q_value', 'pass', 'Q.Value', 'Global.Q.Value', 'apex_rt', 'start_rt',
            'end_rt', 'RT', 'RT.Start', 'RT.Stop', 'Predicted.RT', 'peak']
    tables = {}
    for k, v in sets.items():
        t = v.head(args.max_rows)[cols].copy()
        t['protein'] = t['protein'].astype(str).str.slice(0, 40)
        t = t.astype(object).where(pd.notna(t), None)
        tables[k] = t.values.tolist()
    out['table_cols'] = ['Run', 'Precursor', 'Protein', 'Osprey q', 'Osprey pass', 'DIA-NN q', 'DIA-NN global q',
                         'Osprey apex', 'Osprey start', 'Osprey end', 'DIA-NN RT', 'DIA-NN start', 'DIA-NN stop',
                         'DIA-NN predicted RT', 'Peaks']
    out['tables'] = tables
    out['runs_short'] = [r[-2:] for r in runs]

    # Venn on precursor-run pairs: in both only when both tools pass it at 1% on the same peak.
    o_id, d_id = df['o_id'].values, df['d_id'].values
    agree = df['osprey_fate'].values == FATES[0]
    out['venn'] = {'both': int(agree.sum()), 'osprey': int((o_id & ~agree).sum()), 'diann': int((d_id & ~agree).sum()),
                   'both_1pct_different_peak': int((o_id & d_id & (df['peak'].values == 'different peak')).sum())}

    # Disagreement by each tool's own log10 intensity and own RT.
    out['fates'] = FATES
    rt_edges = np.arange(0, np.ceil(np.nanmax(df['rt'].values)) + 1, 1.0)
    out['rt_edges'] = rt_edges.tolist()
    for tool, area, rt in (('osprey', 'bounds_area', 'apex_rt'), ('diann', 'Precursor.Quantity', 'RT')):
        sel = df[f'{tool}_fate'].values != ''
        fates = df[f'{tool}_fate'].values[sel]
        with np.errstate(divide='ignore', invalid='ignore'):
            li = np.log10(df[area].astype(float).values[sel])
        li[~np.isfinite(li)] = np.nan
        lo, hi = np.nanpercentile(li, [0.5, 99.9])
        i_edges = np.arange(np.floor(lo * 5) / 5, np.ceil(hi * 5) / 5 + 0.01, 0.2)
        out[f'{tool}_i_edges'] = i_edges.round(2).tolist()
        out[f'{tool}_by_intensity'] = fate_histogram(li, fates, i_edges)
        out[f'{tool}_by_rt'] = fate_histogram(df[rt].astype(float).values[sel], fates, rt_edges)
    out['roc'] = {'osprey_vs_diann_truth': roc(df, 'diann', 'osprey'), 'diann_vs_osprey_truth': roc(df, 'osprey', 'diann')}
    return out


def plotly_js():
    """plotly.min.js from the plotly Python package (pip install --user plotly)."""
    import plotly
    path = os.path.join(os.path.dirname(plotly.__file__), 'package_data', 'plotly.min.js')
    with open(path, encoding='utf-8') as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('work_dir')
    ap.add_argument('out_html')
    ap.add_argument('--confident', type=float, default=0.001)
    ap.add_argument('--weak', type=float, default=0.05)
    ap.add_argument('--max-rows', type=int, default=4000)
    ap.add_argument('--title', default=None)
    ap.add_argument('--osprey-run', default='osprey-export-run', help='folder (under the work dir) of the per-run export')
    ap.add_argument('--osprey-experiment', default='osprey-export-experiment')
    ap.add_argument('--diann', default='diann-search-loose', help='folder of the --qvalue 0.5 DIA-NN report')
    args = ap.parse_args()
    df = build(args.work_dir, args)
    data = payload(df, args)
    data['title'] = args.title or 'Osprey vs DIA-NN: ' + os.path.basename(os.path.normpath(args.work_dir))
    data['source'] = os.path.abspath(args.work_dir)
    template = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'compare_osprey_diann.html'),
                    encoding='utf-8').read()
    page = template.replace('__TITLE__', html.escape(data['title'])).replace(
        '__DATA__', json.dumps(data, allow_nan=False, default=float).replace('</', '<\\/'))
    # Plotly inline, last so its text is never searched for the other placeholders: viewers that
    # block external scripts (the Claude Code file panel) render a CDN-loaded page without plots.
    page = page.replace('__PLOTLY__', plotly_js(), 1)
    with open(args.out_html, 'w', encoding='utf-8') as f:
        f.write(page)
    print(f"{args.out_html}: {data['experiment']}, disagreements {data['disagree_counts']}")


if __name__ == '__main__':
    sys.exit(main())
