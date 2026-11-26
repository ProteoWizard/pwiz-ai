#!/usr/bin/env python3
"""
Build-ShuffledProteins.py

Derive a RANDOM-PROTEIN variant of an Osprey library in the Carafe entrapment layout: the protein lists of
the forward peptides (targets and entrapment together) are permuted among those peptides, so every protein
keeps its peptide count but holds a random set of peptides. Grouping then carries no biology, and entrapment
lands on proteins that also hold targets, so an entrapment FDP can see any protein boost.

Read beside the other variants of the same drop:
    standard (entrapment on its own proteins)   classical FDRBench accounting, blind to protein boosting
    split-sized (Build-ProteinShuffledEntrapment.py --in-targets)   real grouping, FDP sees the boost
    random-protein (this script)                random grouping, same peptides-per-protein distribution
    single-peptide (Build-PerPeptideProteins.py)  no grouping at all
split minus random is what TRUE biological grouping adds; random minus single-peptide is what grouping adds
by chance (more attempts per protein at a detectable peptide). Works for any tool that reads the manifest
(Osprey --decoys-in-library) or a FASTA built from it (DIA-NN, seaad_peptides.py).

Peptides per protein (library peptides, not residues: the number of chances a protein gets at a detectable
peptide) is preserved exactly, because whole protein-list strings move between peptides. The script prints
that histogram before and after, and the target and entrapment peptides per protein after.

-------------------------------------------------------------------------
Rule (manifest columns: sequence, decoy, proteins, peptide_type, peptide_pair_index):

    every original accession is renamed to a neutral sp|RP<n>|RP<n>_HUMAN (first-appearance order), so no
        _p_target or _pepNNNNN token survives and no name tells a tool which proteins are entrapment
    the distinct target and p_target sequences, in manifest order, receive the renamed protein lists in a
        random permutation (numpy default_rng(--seed))
    decoy / p_decoy proteins = "decoy_" + each accession of the paired target / p_target row

Entrapment is identified by SEQUENCE only (manifest peptide_type, or assign.tsv). DIA-NN FDP must not use the
_p_target suffix with this library. assign.tsv: sequence, new_acc, on_target (1 when one of the entrapment
peptide's proteins also holds a target peptide), orig_proteins; split_calibration.py reads on_target, and
the script prints the --n-target / --n-on to pass it.

usage:
    python Build-ShuffledProteins.py --library-dir <dir> --out-dir <dir> [--seed N] [--copy]
"""
import argparse
import os
import shutil
import sys

import numpy as np
import pandas as pd

MANIFEST = 'osprey_library_db_pairing.tsv'
LINKED = ('carafe_spectral_library.tsv', 'osprey_library_db_peptides.fasta')
BINS = [1, 2, 3, 5, 10, 20, 50, 100, 200, 500, 10 ** 9]


def histogram(seq_prot, label):
    """Peptides per protein over distinct forward sequences; seq_prot: sequence -> ';'-joined proteins."""
    acc = seq_prot.str.split(';').explode()
    size = acc.groupby(acc).size()
    cut = pd.cut(size, BINS, right=False).value_counts().sort_index()
    print(f'{label}: {len(size)} proteins, median {size.median():.0f}, mean {size.mean():.1f} peptides per protein')
    print('   ' + '  '.join(f'{iv.left}-{iv.right - 1 if iv.right < 10 ** 9 else "+"}:{n}' for iv, n in cut.items()))
    return size


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[1])
    ap.add_argument('--library-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--seed', type=int, default=20261126)
    ap.add_argument('--copy', action='store_true', help='copy library files instead of hard-linking')
    a = ap.parse_args()

    src = os.path.join(a.library_dir, MANIFEST)
    if not os.path.isfile(src):
        sys.exit(f'No pairing manifest: {src}')
    if os.path.abspath(a.out_dir) == os.path.abspath(a.library_dir):
        sys.exit('--out-dir must differ from --library-dir')
    os.makedirs(a.out_dir, exist_ok=True)

    man = pd.read_csv(src, sep='\t', dtype=str, keep_default_na=False)
    print(man.peptide_type.value_counts().to_dict())

    is_fwd = man.peptide_type.isin(['target', 'p_target'])
    # A shuffle-entrapment sequence drawn from two targets has two rows with different lists (354 in the
    # 20260817 drop): merge them so it stays a member of every protein it was in.
    order = man.sequence[is_fwd].drop_duplicates()
    merged = man[is_fwd].groupby('sequence', sort=False).proteins.agg(
        lambda s: ';'.join(dict.fromkeys(p for l in s for p in l.split(';'))))
    fwd = pd.DataFrame({'proteins': merged.reindex(order.values)})
    print(f'{(man[is_fwd].groupby("sequence").proteins.nunique() > 1).sum()} sequences with lists merged')
    before = histogram(fwd.proteins, 'before')

    rename = {}
    for prots in fwd.proteins:
        for p in prots.split(';'):
            if p not in rename:
                n = len(rename) + 1
                rename[p] = f'sp|RP{n:07d}|RP{n:07d}_HUMAN'
    renamed = fwd.proteins.map(lambda s: ';'.join(rename[p] for p in s.split(';')))
    perm = np.random.default_rng(a.seed).permutation(len(renamed))
    new = pd.Series(renamed.values[perm], index=renamed.index)
    after = histogram(new, 'after')
    if not np.array_equal(np.sort(before.values), np.sort(after.values)):
        sys.exit('peptides-per-protein distribution changed')

    out = man.copy()
    out.loc[is_fwd, 'proteins'] = out.sequence[is_fwd].map(new)
    for fwd_type, decoy_type in (('target', 'decoy'), ('p_target', 'p_decoy')):
        f = out[out.peptide_type == fwd_type].drop_duplicates('peptide_pair_index')
        by_pair = dict(zip(f.peptide_pair_index, f.proteins))
        is_d = out.peptide_type == decoy_type
        mapped = out.peptide_pair_index[is_d].map(by_pair)
        if mapped.isna().any():
            sys.exit(f'{decoy_type}: {int(mapped.isna().sum())} rows have no {fwd_type} pair')
        out.loc[is_d, 'proteins'] = mapped.map(lambda s: ';'.join('decoy_' + p for p in s.split(';')))
    if out.proteins.str.contains(r'_pep\d|_p_target', regex=True).any():
        sys.exit('a rewritten accession still carries a _pepNNNNN or _p_target token')
    out.to_csv(os.path.join(a.out_dir, MANIFEST), sep='\t', index=False, lineterminator='\n')

    # Target and entrapment peptides per protein after the shuffle; on_target = shares a protein with a target
    entrap = set(man.sequence[man.peptide_type == 'p_target']) - set(man.sequence[man.peptide_type == 'target'])
    acc = new.str.split(';').explode()
    is_e = acc.index.isin(list(entrap))
    has_target = set(acc[~is_e])
    histogram(new[~new.index.isin(list(entrap))], 'after, target peptides only')
    histogram(new[new.index.isin(list(entrap))], 'after, entrapment peptides only')
    on = new[new.index.isin(list(entrap))].map(lambda s: int(any(p in has_target for p in s.split(';'))))
    n_t = len(new) - len(entrap)
    print(f'mixed proteins: {acc[is_e].nunique() and len(set(acc[is_e]) & has_target)} of {acc.nunique()}; '
          f'entrapment on target-holding proteins {on.sum()} of {len(on)}')
    print(f'split_calibration.py: --n-target {n_t} --n-on {on.sum()}  (manifest counts; take r from the '
          f'peptides the spectral library holds if it lists fewer)')

    orig = fwd.proteins
    with open(os.path.join(a.out_dir, 'assign.tsv'), 'w', newline='\n') as f:
        f.write('sequence\tnew_acc\ton_target\torig_proteins\n')
        for seq, o in on.items():
            f.write(f'{seq}\t{new[seq]}\t{o}\t{orig[seq]}\n')

    for name in LINKED:
        s = os.path.join(a.library_dir, name)
        d = os.path.join(a.out_dir, name)
        if not os.path.isfile(s) or os.path.exists(d):
            continue
        if a.copy:
            shutil.copy2(s, d)
        else:
            os.link(s, d)
    print('done:', a.out_dir)


if __name__ == '__main__':
    main()
