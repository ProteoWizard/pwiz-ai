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

A library paired through a pairing manifest (`--decoy-pairing-manifest`) can have Osprey take its protein accessions
from the manifest's `proteins` column, which would restore the _p_target accessions: pass the manifest too, and a
copy with the same re-filing is written beside the output library. With the manifest, a DecoyPairs table in the
pre-contract shape (older CarafeSharp) is also upgraded to the columns current Osprey reads.

Usage:
  attach_entrapment.py <in .blib> <out .blib> [<in manifest .tsv> <out manifest .tsv>]
"""
import shutil
import sqlite3
import sys

MARKER = '_p_target'
TAB = chr(9)
CRLF = chr(13) + chr(10)


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
    # A provenance note where the library has the table (older CarafeSharp .blibs do not).
    if con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'LibMetadata'").fetchone():
        con.execute("INSERT OR REPLACE INTO LibMetadata(key, value) VALUES ('fdrgap.note', "
                    "'entrapment rows filed under their paired target accessions (attach_entrapment.py)')")
    if len(sys.argv) >= 5:
        upgrade_decoy_pairs(con, sys.argv[3])
    con.commit()
    left = con.execute('SELECT COUNT(*) FROM RefSpectraProteins rp JOIN Proteins p ON p.id = rp.ProteinId '
                       "WHERE instr(p.accession, ?) > 0", (MARKER,)).fetchone()[0]
    con.close()
    print(f'{len(remap)} entrapment proteins remapped ({created} accessions created), '
          f'{n} RefSpectraProteins rows updated, {left} rows still on a {MARKER} accession -> {dst}')
    if left:
        sys.exit(1)
    if len(sys.argv) >= 5:
        attach_manifest(sys.argv[3], sys.argv[4])


def upgrade_decoy_pairs(con, manifest):
    """Rewrite a DecoyPairs table in the pre-contract shape (PairID, no TargetRefSpectraID; CarafeSharp before
    2026-10) to the one Osprey reads now: PairingID is the manifest's peptide_pair_index, looked up by sequence,
    and a decoy's TargetRefSpectraID is the target sharing its old PairID (one target and one decoy each)."""
    cols = [r[1] for r in con.execute('PRAGMA table_info(DecoyPairs)')]
    if 'PairID' not in cols:
        return
    index = {}
    with open(manifest, encoding='utf-8') as fin:
        header = fin.readline().rstrip(CRLF).split(TAB)
        seq_col, pair_col = header.index('sequence'), header.index('peptide_pair_index')
        for line in fin:
            fields = line.rstrip(CRLF).split(TAB)
            index[fields[seq_col]] = int(fields[pair_col])
    rows = con.execute('SELECT d.RefSpectraID, d.IsDecoy, d.IsEntrapment, d.PairID, d.Method, r.peptideSeq '
                       'FROM DecoyPairs d JOIN RefSpectra r ON r.id = d.RefSpectraID').fetchall()
    target_of = {pid: ref for ref, dec, _, pid, _, _ in rows if not dec}
    new = [(ref, dec, ent, index[seq], target_of.get(pid) if dec else None, meth)
           for ref, dec, ent, pid, meth, seq in rows]
    con.execute('DROP TABLE DecoyPairs')
    con.execute('CREATE TABLE DecoyPairs (RefSpectraID INTEGER NOT NULL PRIMARY KEY, IsDecoy INTEGER NOT NULL, '
                'IsEntrapment INTEGER NOT NULL, PairingID INTEGER NOT NULL, '
                'TargetRefSpectraID INTEGER REFERENCES RefSpectra(id), Method TEXT)')
    con.executemany('INSERT INTO DecoyPairs VALUES (?, ?, ?, ?, ?, ?)', new)
    con.execute('CREATE INDEX idx_DecoyPairs_TargetRefSpectraID ON DecoyPairs(TargetRefSpectraID)')
    unpaired = sum(1 for r in new if r[1] and r[4] is None)
    print(f'DecoyPairs upgraded to PairingID/TargetRefSpectraID: {len(new)} rows, {unpaired} decoys without a target')


def attach_manifest(src, dst):
    changed = 0
    with open(src, encoding='utf-8') as fin, open(dst, 'w', encoding='utf-8', newline='') as fout:
        header = fin.readline()
        fout.write(header)
        col = header.rstrip(CRLF).split(TAB).index('proteins')
        for line in fin:
            fields = line.rstrip(CRLF).split(TAB)
            if MARKER in fields[col]:
                fields[col] = fields[col].replace(MARKER, '')
                changed += 1
            fout.write(TAB.join(fields) + chr(10))
    print(f'{changed} manifest rows re-filed under their target accessions -> {dst}')


if __name__ == '__main__':
    main()
