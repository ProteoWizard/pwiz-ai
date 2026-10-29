"""Protein-group FDP split by how many peptides each group was detected with (TODO-20261028_osprey_diann_fdr_gap.md).

Single-peptide proteins must be detectable (Mike, 2026-10-28), and a global protein FDR controls the overall rate,
not the rate inside the one-peptide class - so every arm reports both. A group is entrapment when every accession
carries the suffix (Osprey's FDRBench naming, <target accession>_p_target): measure on a library whose entrapment
keeps its own proteins, not on an attach_entrapment.py copy. FDP is the combined estimator 2 N_e / (N_t + N_e) at
r = 1 (protein entrapment ratio of the 1:1 libraries here).

  Osprey  <arm dir>\\osprey.blib: Proteins.QValue; detected peptides = distinct peptideSeq of linked RefSpectra with
          score (experiment precursor q) <= --q
  DIA-NN  <dir>\\report.parquet: Global.PG.Q.Value; detected peptides = distinct Stripped.Sequence with
          Global.Q.Value <= --q

Usage:
  protein_split.py <arm dir or DIA-NN search dir> [more ...] [--q 0.01] [--suffix _p_target]
"""
import argparse
import os
import sqlite3

import pandas as pd


def is_entrapment(group, suffix):
    accs = [a.strip() for a in str(group).replace(',', ';').split(';') if a.strip()]
    return bool(accs) and all(a.endswith(suffix) for a in accs)


def osprey_groups(arm_dir, q):
    con = sqlite3.connect(f"file:{os.path.join(arm_dir, 'osprey.blib')}?mode=ro", uri=True)
    groups = pd.read_sql_query('SELECT id AS gid, accession AS grp, QValue AS gq FROM Proteins', con)
    detected = pd.read_sql_query(
        'SELECT rp.ProteinId AS gid, COUNT(DISTINCT r.peptideSeq) AS n FROM RefSpectraProteins rp '
        'JOIN RefSpectra r ON r.id = rp.RefSpectraId WHERE r.score <= ? GROUP BY rp.ProteinId', con, params=(q,))
    con.close()
    groups = groups[~groups['grp'].str.lower().str.startswith('decoy_')]
    return groups.merge(detected, on='gid', how='left').fillna({'n': 0})


def diann_groups(search_dir, q):
    d = pd.read_parquet(os.path.join(search_dir, 'report.parquet'),
                        columns=['Protein.Group', 'Stripped.Sequence', 'Global.Q.Value', 'Global.PG.Q.Value'])
    groups = d.groupby('Protein.Group', as_index=False).agg(gq=('Global.PG.Q.Value', 'min'))
    detected = (d[d['Global.Q.Value'] <= q].groupby('Protein.Group')['Stripped.Sequence'].nunique()
                .rename('n').reset_index())
    return groups.merge(detected, on='Protein.Group', how='left').fillna({'n': 0}).rename(columns={'Protein.Group': 'grp'})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dirs', nargs='+')
    ap.add_argument('--q', type=float, default=0.01)
    ap.add_argument('--suffix', default='_p_target')
    args = ap.parse_args()
    for path in args.dirs:
        diann = os.path.exists(os.path.join(path, 'report.parquet'))
        g = diann_groups(path, args.q) if diann else osprey_groups(path, args.q)
        g = g[g['gq'] <= args.q].copy()
        g['entrap'] = g['grp'].map(lambda s: is_entrapment(s, args.suffix))
        print(f'{path} ({"DIA-NN" if diann else "Osprey"}), protein groups at q <= {args.q}:')
        for label, mask in (('1 detected peptide', g['n'] == 1), ('>= 2 detected peptides', g['n'] >= 2),
                            ('no detected peptide', g['n'] == 0), ('all', g['n'] >= 0)):
            n = int(mask.sum())
            ne = int((mask & g['entrap']).sum())
            print(f'  {label:24s} {n:6d} groups, {ne:4d} entrapment, FDP {2 * ne / n if n else 0:.2%}')


if __name__ == '__main__':
    main()
