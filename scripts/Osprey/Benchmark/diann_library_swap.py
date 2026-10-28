"""Give Osprey DIA-NN's predicted spectra and RTs for exactly the peptides of an Osprey library, decoys
included, to separate library quality from Osprey's scoring (Run-DiannEntrapment.ps1 -Steps swap-*).

  fasta   <osprey.predicted.blib> <out.fasta> <out map.tsv>
          every peptide of the library - targets, entrapment and decoys - once, under a unique header,
          for DIA-NN's predictor with --cut "" (no digest); the map keeps each peptide's accessions
  convert <diann library.parquet> <map.tsv> <out library.tsv>
          DIA-NN's exported library as the DIA-NN TSV Osprey reads, with the Osprey library's protein
          accessions (decoys keep their decoy_ prefix) and a Decoy column, streamed in batches

The decoys are predicted by DIA-NN too, so targets and decoys share one predictor: a mixed library
would let the classifier tell decoys by their predictor. Osprey pairs them with the one command's
pairing manifest (--decoys-in-library --decoy-pairing-manifest).
"""
import sqlite3
import sys

import pyarrow as pa
import pyarrow.csv as pacsv
import pyarrow.parquet as pq

COLUMNS = {  # DIA-NN parquet -> the TSV names Osprey's DiannTsvLoader reads
    'Precursor.Mz': 'PrecursorMz', 'Precursor.Charge': 'PrecursorCharge', 'Modified.Sequence': 'ModifiedPeptide',
    'Stripped.Sequence': 'StrippedPeptide', 'Product.Mz': 'FragmentMz', 'Relative.Intensity': 'RelativeIntensity',
    'Fragment.Type': 'FragmentType', 'Fragment.Series.Number': 'FragmentSeriesNumber',
    'Fragment.Charge': 'FragmentCharge', 'Fragment.Loss.Type': 'FragmentLossType', 'RT': 'NormalizedRetentionTime',
}


def fasta(blib, out_fasta, out_map):
    con = sqlite3.connect(f'file:{blib}?mode=ro', uri=True)
    rows = con.execute('SELECT r.peptideSeq, p.accession FROM RefSpectra r '
                       'JOIN RefSpectraProteins rp ON rp.RefSpectraId = r.id '
                       'JOIN Proteins p ON p.id = rp.ProteinId').fetchall()
    con.close()
    accs = {}
    for seq, accession in rows:
        for a in accession.split(';'):
            if a.strip():
                accs.setdefault(seq, set()).add(a.strip())
    decoys = sum(1 for v in accs.values() if all(a.lower().startswith('decoy_') for a in v))
    with open(out_fasta, 'w', newline='\n') as f, open(out_map, 'w', newline='\n') as m:
        m.write('peptide\tproteins\tdecoy\n')
        for i, seq in enumerate(sorted(accs)):
            f.write(f'>P{i}\n{seq}\n')
            v = sorted(accs[seq])
            m.write(f"{seq}\t{';'.join(v)}\t{int(all(a.lower().startswith('decoy_') for a in v))}\n")
    print(f'{len(accs)} peptides ({decoys} decoy) -> {out_fasta}')


def convert(parquet, map_tsv, out_tsv):
    proteins, decoy = {}, {}
    with open(map_tsv) as f:
        next(f)
        for line in f:
            seq, prot, d = line.rstrip('\n').split('\t')
            proteins[seq], decoy[seq] = prot, int(d)
    reader = pq.ParquetFile(parquet)
    sink = open(out_tsv, 'wb')
    writer = None
    n = missing = 0
    for batch in reader.iter_batches(batch_size=500_000, columns=list(COLUMNS)):
        t = batch.to_pydict()
        seqs = t['Stripped.Sequence']
        prot = [proteins.get(s) for s in seqs]
        missing += sum(p is None for p in prot)
        out = {COLUMNS[k]: v for k, v in t.items()}
        out['ProteinId'] = [p or '' for p in prot]
        out['Decoy'] = [decoy.get(s, 0) for s in seqs]
        table = pa.table(out)
        if writer is None:
            # pyarrow quotes header names whatever the quoting style, so the header is written here.
            sink.write(('\t'.join(table.column_names) + '\n').encode())
            writer = pacsv.CSVWriter(sink, table.schema, write_options=pacsv.WriteOptions(
                delimiter='\t', quoting_style='none', include_header=False))
        writer.write_table(table)
        n += len(seqs)
    writer.close()
    sink.close()
    print(f'{n} fragment rows -> {out_tsv}; {missing} rows of peptides absent from the map')


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == 'fasta':
        fasta(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == 'convert':
        convert(*sys.argv[2:])
    else:
        sys.exit(__doc__)
