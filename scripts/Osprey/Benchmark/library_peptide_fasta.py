"""Write a predicted Osprey library's target and entrapment peptides as a peptide FASTA for DIA-NN.

One entry per peptide and protein accession, so DIA-NN (with --cut "") predicts exactly the peptides
Osprey searches and infers proteins from the same peptide-to-protein map. Decoys (accessions prefixed
decoy_) are left out: DIA-NN makes its own.

Usage: library_peptide_fasta.py <osprey.predicted.blib> <out.fasta> <entrapment accession suffix>
"""
import sqlite3
import sys


def main(blib, out_fasta, suffix):
    con = sqlite3.connect(f'file:{blib}?mode=ro', uri=True)
    rows = con.execute(
        'SELECT r.peptideSeq, p.accession FROM RefSpectra r '
        'JOIN RefSpectraProteins rp ON rp.RefSpectraId = r.id '
        'JOIN Proteins p ON p.id = rp.ProteinId').fetchall()
    con.close()
    proteins = {}
    for seq, accessions in rows:
        for accession in accessions.split(';'):
            accession = accession.strip()
            if accession and not accession.lower().startswith('decoy_'):
                proteins.setdefault(seq, set()).add(accession)

    def is_entrapment(seq):
        return all(a.endswith(suffix) for a in proteins[seq])

    entrapment = sum(1 for s in proteins if is_entrapment(s))
    targets = len(proteins) - entrapment
    with open(out_fasta, 'w', newline='\n') as f:
        for seq in sorted(proteins):
            for accession in sorted(proteins[seq]):
                f.write(f'>{accession}\n{seq}\n')
    print(f'{len(proteins)} peptides: {targets} target, {entrapment} entrapment (r = {entrapment / targets:.4f}), '
          f'{sum(len(v) for v in proteins.values())} entries -> {out_fasta}')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
