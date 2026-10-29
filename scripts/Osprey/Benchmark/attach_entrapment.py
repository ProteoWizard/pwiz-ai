"""Copy an Osprey entrapment library with every entrapment row filed under its paired target's real accession.

Osprey names an entrapment peptide's protein after its paired target's with FDRBench's _p_target marker
(sp|P55011_p_target|S12A2_HUMAN_p_target), so entrapment forms proteins of its own and almost never enters
the protein-informed second-pass competition (OSPREY_PASS2_QVALUE=protein-compact, the default), whose
stratum is the proteins with >= 2 first-pass peptides. Entrapment then cannot measure that competition's
error rate (TODO-20261028_osprey_diann_fdr_gap.md, Finding 2). Filed under the real accession, the entrapment
peptides of a detected protein enter the stratum with it, as absent peptides of a present protein - what a
false target inside a detected protein is.

The copy breaks rule 4 of the library contract (entrapment accessions carry _p_target), so label entrapment
by sequence afterwards (the peptide FASTA), not by accession. Protein-level FDP cannot be measured on it.

Usage:
  attach_entrapment.py <in .blib> <out .blib>
"""
import shutil
import sqlite3
import sys

MARKER = '_p_target'


def main():
    src, dst = sys.argv[1], sys.argv[2]
    shutil.copyfile(src, dst)
    con = sqlite3.connect(dst)
    prot = {acc: i for i, acc in con.execute('SELECT id, accession FROM Proteins')}
    remap, created = {}, 0
    for acc, i in list(prot.items()):
        if MARKER in acc:
            real = acc.replace(MARKER, '')
            if real not in prot:
                prot[real] = con.execute('INSERT INTO Proteins(accession) VALUES (?)', (real,)).lastrowid
                created += 1
            remap[i] = prot[real]
    con.execute('CREATE TEMP TABLE m(old INTEGER PRIMARY KEY, new INTEGER)')
    con.executemany('INSERT INTO m VALUES (?, ?)', remap.items())
    n = con.execute('UPDATE RefSpectraProteins SET ProteinId = (SELECT new FROM m WHERE old = ProteinId) '
                    'WHERE ProteinId IN (SELECT old FROM m)').rowcount
    con.execute("INSERT OR REPLACE INTO LibMetadata(key, value) VALUES ('fdrgap.note', "
                "'entrapment rows filed under their paired target accessions (attach_entrapment.py)')")
    con.commit()
    left = con.execute('SELECT COUNT(*) FROM RefSpectraProteins rp JOIN Proteins p ON p.id = rp.ProteinId '
                       "WHERE instr(p.accession, ?) > 0", (MARKER,)).fetchone()[0]
    con.close()
    print(f'{len(remap)} entrapment proteins remapped ({created} accessions created), '
          f'{n} RefSpectraProteins rows updated, {left} rows still on a {MARKER} accession -> {dst}')
    if left:
        sys.exit(1)


if __name__ == '__main__':
    main()
