#!/usr/bin/env python3
"""
Build-PerPeptideProteins.py

Derive a PER-PEPTIDE-PROTEIN variant of an Osprey library in the Carafe
entrapment layout: every distinct peptide sequence becomes the only peptide of
its own protein, so no tool can gain anything from protein grouping. Searched
next to the split variant (Build-ProteinShuffledEntrapment.py --in-targets),
the difference is what each tool gains from protein information ("protein
boosting") over its plain spectrum scoring.

Why not Carafe's own per-peptide accessions (sp|P12345_pep00019|...): Osprey's
CarafeProteinIdNormalizer strips the _pepNNNNN suffix on load, so Osprey
regroups them into real proteins while DIA-NN cannot. That made the original
"DIA-NN loses ~15% on per-peptide accessions" comparison one-sided
(2026-11-07 bisection; Brendan MacLean, 2026-11-25). The accessions written
here (sp|PP0000001|PP0000001_HUMAN) contain no _pepNNNNN token.

Osprey takes proteins from the pairing manifest in --decoys-in-library mode, so
only the manifest is rewritten. The spectral library TSV and the peptide FASTA
are hard-linked (or copied with --copy). The derived .blib is NOT linked: the
split variants carry their own, so let Osprey rebuild it against this manifest.

-------------------------------------------------------------------------
Assignment rule (manifest columns: sequence, decoy, proteins, peptide_type,
peptide_pair_index; types target, p_target, decoy, p_decoy):

    each distinct target or p_target sequence, in manifest order, gets
        sp|PP<n>|PP<n>_HUMAN                          if it is a target sequence
        sp|PP<n>_p_target|PP<n>_HUMAN_p_target        if it is entrapment only
    decoy / p_decoy proteins = "decoy_" + the accession of the target / p_target
        row with the same peptide_pair_index

Entrapment stays identifiable by the FDRBench _p_target marker, so the DIA-NN
FASTA built from this manifest (seaad_peptides.py) and fdrbench/entrapment
readers need no assign.tsv. assign.tsv is still written (sequence, new_acc,
on_target 0, orig_proteins) for tools that expect it.

usage:
    python Build-PerPeptideProteins.py --library-dir <dir> --out-dir <dir> [--copy]
"""
import argparse
import os
import shutil
import sys

import pandas as pd

MANIFEST = 'osprey_library_db_pairing.tsv'
LINKED = ('carafe_spectral_library.tsv', 'osprey_library_db_peptides.fasta')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[1])
    ap.add_argument('--library-dir', required=True)
    ap.add_argument('--out-dir', required=True)
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

    fwd = man[man.peptide_type.isin(['target', 'p_target'])]
    target_seqs = set(fwd.sequence[fwd.peptide_type == 'target'])
    acc = {}
    for seq in fwd.sequence:
        if seq not in acc:
            n = len(acc) + 1
            acc[seq] = (f'sp|PP{n:07d}|PP{n:07d}_HUMAN' if seq in target_seqs
                        else f'sp|PP{n:07d}_p_target|PP{n:07d}_HUMAN_p_target')
    n_entrap = sum(s not in target_seqs for s in acc)
    print(f'{len(acc)} distinct peptides: {len(acc) - n_entrap} target, {n_entrap} entrapment only')

    out = man.copy()
    is_fwd = out.peptide_type.isin(['target', 'p_target'])
    out.loc[is_fwd, 'proteins'] = out.sequence[is_fwd].map(acc)
    for fwd_type, decoy_type in (('target', 'decoy'), ('p_target', 'p_decoy')):
        f = out[out.peptide_type == fwd_type]
        by_pair = dict(zip(f.peptide_pair_index, f.proteins))
        if len(by_pair) != len(f):
            sys.exit(f'{fwd_type}: peptide_pair_index is not unique ({len(f)} rows, {len(by_pair)} indexes)')
        is_d = out.peptide_type == decoy_type
        mapped = out.peptide_pair_index[is_d].map(by_pair)
        if mapped.isna().any():
            sys.exit(f'{decoy_type}: {int(mapped.isna().sum())} rows have no {fwd_type} pair')
        out.loc[is_d, 'proteins'] = 'decoy_' + mapped
    if out.proteins.str.contains(r'_pep\d', regex=True).any():
        sys.exit('a rewritten accession still carries a _pepNNNNN token')
    out.to_csv(os.path.join(a.out_dir, MANIFEST), sep='\t', index=False, lineterminator='\n')

    # Checks: one forward accession per sequence, every forward accession used by one sequence only
    fwd_out = out[is_fwd].drop_duplicates(['sequence', 'proteins'])
    per_seq = fwd_out.groupby('sequence').proteins.nunique().max()
    per_acc = fwd_out.groupby('proteins').sequence.nunique().max()
    print(f'max accessions per peptide {per_seq}, max peptides per accession {per_acc}')
    if per_seq != 1 or per_acc != 1:
        sys.exit('per-peptide check failed')

    with open(os.path.join(a.out_dir, 'assign.tsv'), 'w', newline='\n') as f:
        f.write('sequence\tnew_acc\ton_target\torig_proteins\n')
        entrap = man[(man.peptide_type == 'p_target') & ~man.sequence.isin(target_seqs)].drop_duplicates('sequence')
        for seq, prot in zip(entrap.sequence, entrap.proteins):
            f.write(f'{seq}\t{acc[seq]}\t0\t{prot}\n')

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
