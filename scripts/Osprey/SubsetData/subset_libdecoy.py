"""Cut the library-decoy + entrapment variant of the Stellar subset out of stellar-libdecoy.

For every target peptide of an existing subset library (subset_library.py output), takes its
whole pairing group from the Carafe library - target, shuffled entrapment (p_target), and the
decoy of each - restricted to precursors inside the isolation window. Shuffles and reversals
keep the target's composition, so the whole group falls in the same window. ProteinID and the
pairing manifest's protein column get the SAME synthetic accession the subset library gave the
target, decorated the way Carafe decorates real ones (decoy_ prefix, _p_target suffix), so the
two libraries share their protein grouping.

Usage: python subset_libdecoy.py SUBSET_LIB.tsv CARAFE_LIB.tsv PAIRING.tsv OUT_LIB.tsv OUT_PAIRING.tsv
                                 --mz-lo L --mz-hi H
"""
import argparse


def entrap(acc):
    """sp|X|Y -> sp|X_p_target|Y_p_target, the way Carafe names an entrapment protein."""
    parts = acc.split('|')
    return '|'.join([parts[0]] + [p + '_p_target' for p in parts[1:]])


def decorate(accessions, peptide_type):
    out = []
    for acc in accessions.split(';'):
        if peptide_type in ('p_target', 'p_decoy'):
            acc = entrap(acc)
        if peptide_type in ('decoy', 'p_decoy'):
            acc = 'decoy_' + acc
        out.append(acc)
    return ';'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('subset_lib')
    ap.add_argument('carafe_lib')
    ap.add_argument('pairing')
    ap.add_argument('out_lib')
    ap.add_argument('out_pairing')
    ap.add_argument('--mz-lo', type=float, required=True)
    ap.add_argument('--mz-hi', type=float, required=True)
    a = ap.parse_args()

    # Target stripped sequence -> synthetic accession(s), from the subset library
    target_prot = {}
    with open(a.subset_lib, encoding='utf-8') as f:
        hdr = f.readline().rstrip('\n').split('\t')
        ci = {h: i for i, h in enumerate(hdr)}
        for line in f:
            p = line.rstrip('\n').split('\t')
            target_prot[p[ci['StrippedPeptide']]] = p[ci['ProteinID']]

    # Pairing groups of those targets
    groups = {}
    target_of_group = {}
    with open(a.pairing, encoding='utf-8') as f:
        phdr = f.readline()
        for line in f:
            seq, decoy, prots, ptype, idx = line.rstrip('\n').split('\t')
            groups.setdefault(idx, []).append((seq, decoy, prots, ptype))
            if ptype == 'target' and seq in target_prot:
                target_of_group[idx] = seq
    seq_prot = {}
    manifest_rows = []
    for idx in sorted(target_of_group, key=int):
        acc = target_prot[target_of_group[idx]]
        for seq, decoy, prots, ptype in groups[idx]:
            new_prot = decorate(acc, ptype)
            seq_prot[seq] = new_prot
            manifest_rows.append('\t'.join([seq, decoy, new_prot, ptype, idx]))

    n_rows = 0
    kept = set()
    with open(a.carafe_lib, encoding='utf-8') as f, open(a.out_lib, 'w', encoding='utf-8', newline='\n') as w:
        header = f.readline()
        w.write(header)
        hdr = header.rstrip('\n').split('\t')
        ci = {h: i for i, h in enumerate(hdr)}
        for line in f:
            cols = line.rstrip('\n').split('\t')
            seq = cols[ci['StrippedPeptide']]
            if seq not in seq_prot:
                continue
            if not (a.mz_lo <= float(cols[ci['PrecursorMz']]) <= a.mz_hi):
                continue
            cols[ci['ProteinID']] = seq_prot[seq]
            w.write('\t'.join(cols) + '\n')
            kept.add((seq, cols[ci['PrecursorCharge']]))
            n_rows += 1
    kept_seqs = {s for s, _ in kept}
    with open(a.out_pairing, 'w', encoding='utf-8', newline='\n') as w:
        w.write(phdr)
        for row in manifest_rows:
            if row.split('\t', 1)[0] in kept_seqs:
                w.write(row + '\n')
    print('groups %d, precursors %d, library rows %d' % (len(target_of_group), len(kept), n_rows))


if __name__ == '__main__':
    main()
