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

Each --osprey run dir is read for fdrbench.pass1.tsv and fdrbench.pass2.tsv. A pass-2 FDRBench holds only rows that
reached pass 2, and rows at q = 1 carry no order, so a find count that stops there is marked '*' and is not a find
rate; read pass 2 by its q columns.
"""
import argparse
import os

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

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


def osprey(path, assign):
    t = pd.read_csv(path, sep='\t', usecols=['peptide', 'mod_peptide', 'charge', 'q_value', 'protein'])
    t = t[~t.protein.astype(str).str.startswith('decoy_')]
    t = t.sort_values('q_value', kind='stable').drop_duplicates(['mod_peptide', 'charge'])
    p = t.peptide.map(assign)
    on, own = (p == 1).values, (p == 0).values
    return t.q_value.values, ~(on | own), on


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
            f = os.path.join(d, f'fdrbench.pass{ps}.tsv')
            if os.path.exists(f):
                report(f'{os.path.basename(os.path.normpath(d))[-32:]} p{ps}', *osprey(f, assign), a.n_on, a.n_target)
    print("* = stops at the last row with q < 1 (pass-2 FDRBench holds only rows that reached pass 2), not a find rate")


if __name__ == '__main__':
    main()
