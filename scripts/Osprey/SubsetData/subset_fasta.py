"""Write the proteins of a subset library as a FASTA.

The synthetic proteins of subset_library.py --synthetic-proteins exist because one isolation
window rarely holds two peptides of one protein. A band of windows over the full gradient does,
so a mid-size subset can keep the real accessions and search against their real sequences.

Default: reads the ProteinID column of one or more subset .tsv libraries (';' joins shared
proteins) and copies each named record from the source FASTA verbatim, in source order, LF
line endings.

With --concatenated there is no source FASTA: each ProteinID value becomes one record whose
sequence is its tryptic peptides concatenated, as SubsetPipelineTest.WriteSubsetProteinFasta()
writes the synthetic proteins of a --synthetic-proteins library (pass '-' for SOURCE).

Usage: python subset_fasta.py SOURCE.fasta OUT.fasta LIB.tsv [LIB2.tsv ...]
       python subset_fasta.py - OUT.fasta LIB.tsv --concatenated
"""
import argparse
import sys


def read_rows(lib_paths, *names):
    for path in lib_paths:
        with open(path, 'r', encoding='utf-8') as f:
            hdr = f.readline().rstrip('\n').split('\t')
            idx = [hdr.index(n) for n in names]
            for line in f:
                cols = line.rstrip('\n').split('\t')
                yield [cols[i] for i in idx]


def write_concatenated(lib_paths, out):
    """Mirror of SubsetPipelineTest.WriteSubsetProteinFasta(): tryptic peptides only, ordinal key order."""
    by_protein = {}
    for pep, prot in read_rows(lib_paths, 'StrippedPeptide', 'ProteinID'):
        if not pep.endswith(('K', 'R')) or pep.startswith('P'):
            continue
        peps = by_protein.setdefault(prot, [])
        if pep not in peps:
            peps.append(pep)
    with open(out, 'w', encoding='utf-8', newline='\n') as w:
        for prot in sorted(by_protein):
            w.write('>' + prot + '\n' + ''.join(by_protein[prot]) + '\n')
    print('concatenated proteins %d, %d residues'
          % (len(by_protein), sum(len(''.join(v)) for v in by_protein.values())))


def write_real(fasta, lib_paths, out):
    wanted = {acc for (prot,) in read_rows(lib_paths, 'ProteinID') for acc in prot.split(';') if acc}
    found = set()
    n_res = 0
    keep = False
    with open(fasta, 'r', encoding='utf-8') as f, open(out, 'w', encoding='utf-8', newline='\n') as w:
        for line in f:
            line = line.rstrip('\r\n')
            if line.startswith('>'):
                acc = line[1:].split(None, 1)[0] if len(line) > 1 else ''
                keep = acc in wanted
                if keep:
                    found.add(acc)
            elif keep:
                n_res += len(line.strip())
            if keep:
                w.write(line + '\n')
    print('proteins %d of %d named, %d residues' % (len(found), len(wanted), n_res))
    missing = wanted - found
    if missing:
        print('not in %s: %s' % (fasta, ', '.join(sorted(missing)[:10])), file=sys.stderr)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('fasta')
    ap.add_argument('out')
    ap.add_argument('libs', nargs='+')
    ap.add_argument('--concatenated', action='store_true',
                    help='write synthetic proteins of concatenated peptides instead of copying records')
    a = ap.parse_args()
    if a.concatenated:
        write_concatenated(a.libs, a.out)
    else:
        write_real(a.fasta, a.libs, a.out)


if __name__ == '__main__':
    main()
