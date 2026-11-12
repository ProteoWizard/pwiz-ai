#!/usr/bin/env python3
"""Search q vs split-entrapment FDP, Osprey and DIA-NN, on a #5011-style split library.

For each arm: precursors kept and the on-target-half FDP at reported q 0.5/1/2/5%, and the precursors found at a true
on-target FDP of 0.5% and 1% (FDP = E * (1 + 1/r) / (T + E), r = on-target entrapment / target peptides, made
monotone from the tail). Precursor level, experiment-wide: Osprey mod_peptide + charge from an FDRBench TSV, DIA-NN
Precursor.Id from report.parquet (Global.Q.Value). The on-target half tests peptide-level FDR; the own half collapses
under any protein-aware step, so it is not read.

usage:
    python split_calibration.py --lib-dir <split library dir> [--osprey <run dir> ...] [--diann <report.parquet> ...]
        [--n-target N --n-on N] [--diann-assign <assign.tsv> --diann-n-target N]

--lib-dir must hold assign.tsv (Build-ProteinShuffledEntrapment.py --in-targets). r must come from the peptides the
searched library really holds; assign.tsv and the manifest list more than the spectral library does. The defaults
are the SEA-AD size-weighted split (target+decoy+entrapment-20260817-split-sized): 1,131,671 target and 565,555
on-target entrapment peptides in carafe_spectral_library.tsv. A DIA-NN arm must search the same peptides with the
Osprey decoys removed: a Carafe TSV with Osprey's decoys but no Decoy flag is searched by DIA-NN as targets.
A DIA-NN library split by its own script (lib_split_entrap.py) has its own draw: pass its assignment (columns
peptide, placement) with --diann-assign and its target count with --diann-n-target; its on-target count is read
from that file. For the SEA-AD A2-sized DIA-NN library: bisect/A2-sized.assign.tsv, 1,129,657 targets.

Each --osprey run dir is read for fdrbench.pass1.tsv and fdrbench.pass2.tsv (or their .gz). A pass-2 FDRBench holds
only rows that reached pass 2, and rows at q = 1 carry no order, so a find count that stops there is marked '*' and
is not a find rate; read pass 2 by its q columns.

Agreement with DIA-NN (--agree <report.parquet>): detection counts alone do not say WHICH precursors a tool finds,
so a count moving toward DIA-NN's can come from precursors DIA-NN itself does not identify. For each Osprey arm and
pass, the real-target precursors it reports at true on-target FDP 1% are matched (modified sequence as UniMod ids,
plus charge, against DIA-NN's Precursor.Id) with the precursors DIA-NN identifies at Q.Value <= --agree-q in at
least one of the SAME runs (read from the arm's run.log command line; all of the report's runs when that is
missing), so a DIA-NN report over more runs than the arm still compares like with like. Reported: Osprey's
count, how many DIA-NN also identifies, Osprey-only, and DIA-NN-only. With --reference <run dir>, every other
arm's precursors LOST and GAINED against the reference are split the same way: a change that only loses
precursors DIA-NN does not identify costs less than its count suggests.
"""
import argparse
import os
import re

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

UNIMOD_BY_MASS = {'57.02': 'UniMod:4', '15.99': 'UniMod:35', '42.01': 'UniMod:1', '79.97': 'UniMod:21'}

QS = (0.005, 0.01, 0.02, 0.05)


def report(name, q, tg, on, n_on, n_t):
    r = n_on / n_t
    T, E = np.cumsum(tg), np.cumsum(on)
    fd = E * (1 + 1 / r) / np.maximum(T + E, 1)
    m = np.minimum.accumulate(fd[::-1])[::-1]
    cells = []
    for lv in QS:
        k = np.searchsorted(q, lv, side='right') - 1
        cells.append(f'{T[k] if k >= 0 else 0:7d} {fd[k] * 100 if k >= 0 else 0:4.2f}%')
    stop = int(np.searchsorted(q, 1.0, side='left')) - 1
    find = []
    for lv in (0.005, 0.01):
        k = min(np.searchsorted(m, lv, side='right') - 1, stop)
        if k < 0:
            find.append('      0 ')
        else:
            cut = k == len(T) - 1 or (k + 1 < len(q) and q[k + 1] >= 1.0)
            find.append(f'{T[k]:7d}' + ('*' if cut else ' '))
    print(f'{name:40s} ' + ' | '.join(cells) + ' || ' + ' '.join(find), flush=True)


def fdp_cut(q, tg, on, n_on, n_t, lv=0.01):
    """Rows (a prefix of the q-sorted table) kept at true on-target FDP lv - the cut report() counts."""
    r = n_on / n_t
    T, E = np.cumsum(tg), np.cumsum(on)
    fd = E * (1 + 1 / r) / np.maximum(T + E, 1)
    m = np.minimum.accumulate(fd[::-1])[::-1]
    stop = int(np.searchsorted(q, 1.0, side='left')) - 1
    return min(np.searchsorted(m, lv, side='right') - 1, stop) + 1


def unimod(modseq):
    """Osprey's C[+57.0215] as DIA-NN's C(UniMod:4)."""
    return re.sub(r'\[([+-]?[\d.]+)\]',
                  lambda m: '(%s)' % UNIMOD_BY_MASS.get('%.2f' % abs(float(m.group(1))), m.group(1)), modseq)


def osprey_table(path, assign):
    t = pd.read_csv(path, sep='\t', usecols=['peptide', 'mod_peptide', 'charge', 'q_value', 'protein'])
    t = t[~t.protein.astype(str).str.startswith('decoy_')]
    t = t.sort_values('q_value', kind='stable').drop_duplicates(['mod_peptide', 'charge'])
    p = t.peptide.map(assign)
    t['on'], t['own'] = (p == 1).values, (p == 0).values
    return t


def osprey(path, assign):
    t = osprey_table(path, assign)
    on, own = t.on.values, t.own.values
    return t.q_value.values, ~(on | own), on


def osprey_found(path, assign, n_on, n_t):
    """Real-target precursor ids (DIA-NN Precursor.Id form) an Osprey FDRBench table reports at true FDP 1%."""
    t = osprey_table(path, assign)
    tg = ~(t.on.values | t.own.values)
    k = fdp_cut(t.q_value.values, tg, t.on.values, n_on, n_t)
    head = t.iloc[:k][tg[:k]]
    return set(head.mod_peptide.map(unimod) + head.charge.astype(str))


def arm_runs(run_dir):
    """Input run names from the arm's run.log command line, or None."""
    log = os.path.join(run_dir, 'run.log')
    if not os.path.exists(log):
        return None
    with open(log, encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'Command:' in line:
                return {os.path.splitext(os.path.basename(p))[0]
                        for p in re.findall(r'\S+\.(?:mzML|raw|d)\b', line, re.IGNORECASE)}
    return None


def diann_confident(report_df, runs, q):
    """Target Precursor.Id values DIA-NN identifies at Q.Value <= q in at least one of runs (all runs if None)."""
    d = report_df
    if runs is not None:
        d = d[d.Run.isin(runs)]
    return set(d.loc[d['Q.Value'] <= q, 'Precursor.Id'])


def fdrbench_path(run_dir, ps):
    f = os.path.join(run_dir, f'fdrbench.pass{ps}.tsv')
    return f if os.path.exists(f) else (f + '.gz' if os.path.exists(f + '.gz') else None)


def diann_assign(path):
    a = pd.read_csv(path, sep='	')
    if 'placement' in a.columns:
        return a.set_index('peptide').placement.map({'on_target': 1, 'own': 0})
    return a.drop_duplicates('sequence').set_index('sequence').on_target


def diann(path, assign):
    d = pq.read_table(path, columns=['Stripped.Sequence', 'Precursor.Id', 'Decoy', 'Global.Q.Value']).to_pandas()
    d = d[d.Decoy == 0].sort_values('Global.Q.Value', kind='stable').drop_duplicates('Precursor.Id')
    p = d['Stripped.Sequence'].map(assign)
    on, own = (p == 1).values, (p == 0).values
    return d['Global.Q.Value'].values, ~(on | own), on


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--lib-dir', required=True)
    ap.add_argument('--osprey', nargs='*', default=[], help='Osprey run directories')
    ap.add_argument('--diann', nargs='*', default=[], help='DIA-NN report.parquet files')
    ap.add_argument('--n-target', type=int, default=1131671)
    ap.add_argument('--n-on', type=int, default=565555)
    ap.add_argument('--diann-assign', help='assignment of a DIA-NN library split by its own draw')
    ap.add_argument('--diann-n-target', type=int, help='target peptides in that DIA-NN library')
    ap.add_argument('--agree', help='DIA-NN report.parquet to measure each Osprey arm\'s agreement against')
    ap.add_argument('--agree-q', type=float, default=0.01, help='DIA-NN run Q.Value for a confident identification')
    ap.add_argument('--reference', help='Osprey run dir to split every other arm\'s lost/gained precursors against')
    a = ap.parse_args()
    assign = pd.read_csv(os.path.join(a.lib_dir, 'assign.tsv'), sep='\t', usecols=['sequence', 'on_target']) \
        .drop_duplicates('sequence').set_index('sequence').on_target
    print(f'{"arm":40s} ' + ' | '.join(f'q{lv * 100:g}%: kept    FDP' for lv in QS) + ' || at FDP 0.5%   1%')
    if a.diann_assign:
        if not a.diann_n_target:
            ap.error('--diann-assign needs --diann-n-target')
        da = diann_assign(a.diann_assign)
        dn_on, dn_t = int((da == 1).sum()), a.diann_n_target
    else:
        da, dn_on, dn_t = assign, a.n_on, a.n_target
    for rep in a.diann:
        report('DIA-NN ' + os.path.basename(os.path.dirname(os.path.abspath(rep))), *diann(rep, da), dn_on, dn_t)
    for d in a.osprey:
        for ps in ('1', '2'):
            f = fdrbench_path(d, ps)
            if f:
                report(f'{os.path.basename(os.path.normpath(d))[-32:]} p{ps}', *osprey(f, assign), a.n_on, a.n_target)
    print("* = stops at the last row with q < 1 (pass-2 FDRBench holds only rows that reached pass 2), not a find rate")
    if a.agree:
        agreement(a, assign)


def agreement(a, assign):
    rep = pq.read_table(a.agree, columns=['Run', 'Precursor.Id', 'Decoy', 'Q.Value']).to_pandas()
    rep = rep[rep.Decoy == 0]
    rep['Run'] = rep.Run.map(lambda r: os.path.splitext(os.path.basename(str(r).replace('\\', '/')))[0])
    print(f'\nAgreement with DIA-NN ({a.agree}; run Q.Value <= {a.agree_q} in the arm\'s runs), real targets at true '
          f'FDP 1%:')
    print(f'{"arm":40s} {"Osprey":>8s} {"both":>8s} {"% both":>7s} {"Osprey only":>12s} {"DIA-NN only":>12s} runs')
    found = {}
    for d in dict.fromkeys(([a.reference] if a.reference else []) + a.osprey):
        runs = arm_runs(d)
        if runs is not None and not runs & set(rep.Run.unique()):
            print(f'{os.path.basename(os.path.normpath(d))[-40:]:40s} none of its runs are in the DIA-NN report')
            continue
        dn = diann_confident(rep, runs, a.agree_q)
        for ps in ('1', '2'):
            f = fdrbench_path(d, ps)
            if not f:
                continue
            o = osprey_found(f, assign, a.n_on, a.n_target)
            found[(d, ps)] = (o, dn)
            both = len(o & dn)
            print(f'{(os.path.basename(os.path.normpath(d))[-37:] + " p" + ps):40s} {len(o):8d} {both:8d} '
                  f'{100 * both / max(len(o), 1):6.1f}% {len(o - dn):12d} {len(dn - o):12d} '
                  f'{len(runs) if runs is not None else "all"}')
    if not a.reference:
        return
    print(f'\nAgainst the reference {os.path.basename(os.path.normpath(a.reference))}: precursors lost and gained, by '
          f'whether DIA-NN identifies them:')
    print(f'{"arm":40s} {"lost":>7s} {"DIA-NN":>7s} {"% DIA-NN":>8s} {"gained":>7s} {"DIA-NN":>7s} {"% DIA-NN":>8s}')
    for d in a.osprey:
        for ps in ('1', '2'):
            if (d, ps) not in found or (a.reference, ps) not in found or d == a.reference:
                continue
            ref, dn = found[(a.reference, ps)]
            o = found[(d, ps)][0]
            lost, gained = ref - o, o - ref
            print(f'{(os.path.basename(os.path.normpath(d))[-37:] + " p" + ps):40s} {len(lost):7d} {len(lost & dn):7d} '
                  f'{100 * len(lost & dn) / max(len(lost), 1):7.1f}% {len(gained):7d} {len(gained & dn):7d} '
                  f'{100 * len(gained & dn) / max(len(gained), 1):7.1f}%')


if __name__ == '__main__':
    main()
