#!/usr/bin/env python3
"""
Build-ProteinShuffledEntrapment.py

Derive a PROTEIN-SHUFFLED entrapment variant of an Osprey library in the Carafe
entrapment layout: every entrapment peptide's protein is reassigned at random
among ALL target + entrapment proteins, so about half the entrapment lands on
target proteins. Targets keep their proteins, and every decoy carries its paired
peptide's (possibly moved) protein, as the library's own construction rule does.
Spectra, sequences and target-decoy pairs are unchanged.

Searched next to the unshuffled library, any difference in a result is caused
by protein information alone. The standard design puts every entrapment peptide
on its own entrapment protein, which never becomes "detected", so it cannot see
FDR inflation from protein-aware scoring; the shuffled arm can. See
pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md (the audit design is
Brendan MacLean's, 2026-11-01).

Osprey takes proteins from the pairing manifest in --decoys-in-library mode, so
only the manifest is rewritten. The spectral library, its .blib and the peptide
FASTA are hard-linked (or copied with --copy) into the output directory.

-------------------------------------------------------------------------
Input directory (the Carafe entrapment library drop):

    carafe_spectral_library.tsv        spectral library (linked)
    carafe_spectral_library.tsv.blib   derived library (linked when present)
    osprey_library_db_pairing.tsv      pairing manifest (rewritten)
    osprey_library_db_peptides.fasta   peptide FASTA (linked when present)

Manifest columns: sequence, decoy, proteins, peptide_type, peptide_pair_index.
peptide_type is target, p_target (entrapment), decoy or p_decoy (decoy of an
entrapment peptide). A p_decoy and its p_target share peptide_pair_index.

-------------------------------------------------------------------------
Assignment rule:

    pool   = sorted distinct accessions of every target and p_target row
    each p_target sequence that is not also a target sequence draws ONE
             accession uniformly from pool (numpy default_rng(seed))
    p_decoy proteins = "decoy_" + its pair's new accession

The default seed 20261101 reproduces the SEA-AD audit library
(1,391,232 entrapment peptides over 41,274 accessions; 696,316 on a target
protein).

Outputs in --out-dir: the rewritten osprey_library_db_pairing.tsv, the linked
library files, and assign.tsv (sequence, new_acc, on_target, orig_proteins),
the per-peptide truth an analysis needs to split entrapment hits by where they
landed.

usage:
    python Build-ProteinShuffledEntrapment.py --library-dir <dir> --out-dir <dir>
        [--seed 20261101] [--copy]
"""
import argparse
import os
import shutil
import sys

import numpy as np
import pandas as pd

MANIFEST = 'osprey_library_db_pairing.tsv'
LINKED = ('carafe_spectral_library.tsv', 'carafe_spectral_library.tsv.blib',
          'osprey_library_db_peptides.fasta')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[1])
    ap.add_argument('--library-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--seed', type=int, default=20261101)
    ap.add_argument('--copy', action='store_true', help='copy library files instead of hard-linking')
    a = ap.parse_args()

    src = os.path.join(a.library_dir, MANIFEST)
    if not os.path.isfile(src):
        sys.exit(f'No pairing manifest: {src}')
    if os.path.abspath(a.out_dir) == os.path.abspath(a.library_dir):
        sys.exit('--out-dir must differ from --library-dir')
    os.makedirs(a.out_dir, exist_ok=True)

    man = pd.read_csv(src, sep='\t', dtype=str, keep_default_na=False)
    pool = sorted(set(man[man.peptide_type.isin(['target', 'p_target'])].proteins.str.split(';').explode()))
    n_target_acc = sum('_p_target' not in x for x in pool)
    print(f'pool {len(pool)} accessions: {n_target_acc} target, {len(pool) - n_target_acc} entrapment')

    target_seqs = set(man.sequence[man.peptide_type == 'target'])
    entrap = man[(man.peptide_type == 'p_target') & ~man.sequence.isin(target_seqs)].drop_duplicates('sequence')
    if entrap.empty:
        sys.exit('No entrapment (p_target) rows in the manifest - nothing to shuffle')
    rng = np.random.default_rng(a.seed)
    draw = rng.integers(0, len(pool), len(entrap))
    assign = dict(zip(entrap.sequence, (pool[i] for i in draw)))

    with open(os.path.join(a.out_dir, 'assign.tsv'), 'w', newline='\n') as f:
        f.write('sequence\tnew_acc\ton_target\torig_proteins\n')
        for seq, prot in zip(entrap.sequence, entrap.proteins):
            acc = assign[seq]
            f.write(f'{seq}\t{acc}\t{int("_p_target" not in acc)}\t{prot}\n')
    on_target = sum('_p_target' not in x for x in assign.values())
    print(f'entrapment peptides reassigned {len(assign)}, now on a target protein {on_target}')

    out = man.copy()
    is_entrap = out.peptide_type == 'p_target'
    new_acc = out.sequence.map(assign)
    sel = is_entrap & new_acc.notna()
    out.loc[sel, 'proteins'] = new_acc[sel]
    acc_by_pair = dict(zip(out.peptide_pair_index[sel], new_acc[sel]))
    is_pdecoy = out.peptide_type == 'p_decoy'
    decoy_acc = out.peptide_pair_index.map(acc_by_pair)
    seld = is_pdecoy & decoy_acc.notna()
    out.loc[seld, 'proteins'] = 'decoy_' + decoy_acc[seld]
    print(f'manifest rows rewritten: p_target {int(sel.sum())}, p_decoy {int(seld.sum())}')
    out.to_csv(os.path.join(a.out_dir, MANIFEST), sep='\t', index=False, lineterminator='\n')

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
