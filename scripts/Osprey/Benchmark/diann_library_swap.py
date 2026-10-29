"""Give Osprey DIA-NN's predicted spectra and RTs for exactly the peptides of an Osprey library, decoys
included, to separate library quality from Osprey's scoring (Run-DiannEntrapment.ps1 -Steps swap-*).

  fasta   <osprey.predicted.blib> <out.fasta> <out map.tsv>
          every peptide of the library - targets, entrapment and decoys - once, under a unique header,
          for DIA-NN's predictor with --cut "" (no digest); the map keeps each peptide's accessions
  convert <diann library.parquet> <map.tsv | -> <out library.tsv>
          DIA-NN's exported library as the DIA-NN TSV Osprey reads, with the Osprey library's protein
          accessions (decoys keep their decoy_ prefix) and a Decoy column, streamed in batches. With -
          for the map, DIA-NN's own Protein.Ids and Decoy 0: DIA-NN's FASTA-predicted library as is,
          for Osprey to search with decoys it generates (no --decoys-in-library)
  export  <osprey.predicted.blib> <out library.tsv>
          the reverse swap: the library's targets (no decoys; DIA-NN makes its own) as a DIA-NN TSV
          library with UniMod modifications, for DIA-NN --lib

The decoys are predicted by DIA-NN too, so targets and decoys share one predictor: a mixed library
would let the classifier tell decoys by their predictor. Osprey pairs them with the one command's
pairing manifest (--decoys-in-library --decoy-pairing-manifest).
"""
import re
import sqlite3
import struct
import sys
import zlib

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
    own = map_tsv == '-'
    if not own:
        with open(map_tsv) as f:
            next(f)
            for line in f:
                seq, prot, d = line.rstrip('\n').split('\t')
                proteins[seq], decoy[seq] = prot, int(d)
    reader = pq.ParquetFile(parquet)
    sink = open(out_tsv, 'wb')
    writer = None
    n = missing = 0
    for batch in reader.iter_batches(batch_size=500_000, columns=list(COLUMNS) + (['Protein.Ids'] if own else [])):
        t = batch.to_pydict()
        seqs = t['Stripped.Sequence']
        prot = t.pop('Protein.Ids') if own else [proteins.get(s) for s in seqs]
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


UNIMOD = {'57.02': 4, '15.99': 35, '42.01': 1, '79.97': 21, '-17.03': 28, '-18.01': 27}
EXPORT_COLUMNS = ['PrecursorMz', 'ModifiedPeptide', 'StrippedPeptide', 'PrecursorCharge', 'NormalizedRetentionTime',
                  'ProteinId', 'FragmentMz', 'RelativeIntensity', 'FragmentType', 'FragmentSeriesNumber',
                  'FragmentCharge', 'FragmentLossType', 'Decoy']
FRAGMENT = re.compile(r'^([abcxyz])(\d+)(?:[-_](.+))?$')


def unimod(modseq):
    def repl(m):
        key = '%.2f' % float(m.group(1))
        if key not in UNIMOD:
            raise ValueError(f'No UniMod id for {m.group(0)} in {modseq}')
        return f'(UniMod:{UNIMOD[key]})'
    return re.sub(r'\[([+-]?[\d.]+)\]', repl, modseq)


def export(blib, out_tsv):
    """Targets of an Osprey .blib as a DIA-NN TSV, by merging three tables walked in RefSpectra id order."""
    con = sqlite3.connect(f'file:{blib}?mode=ro', uri=True)
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'DecoyPairs' in tables:
        decoy_ids = {r[0] for r in con.execute('SELECT RefSpectraID FROM DecoyPairs WHERE IsDecoy = 1')}
    else:
        decoy_ids = set()
    proteins = {}
    for sid, acc in con.execute('SELECT rp.RefSpectraId, p.accession FROM RefSpectraProteins rp '
                                'JOIN Proteins p ON p.id = rp.ProteinId'):
        proteins.setdefault(sid, []).append(acc)
    # Also decoys by accession prefix, as Osprey recognizes them: DecoyPairs holds only paired spectra, so
    # an unpaired decoy (127 in the Astral regression library) is absent from it.
    decoy_ids |= {k for k, v in proteins.items() if all(a.lower().startswith(('decoy_', 'rev_')) for a in v)}
    spectra = con.cursor().execute(
        'SELECT r.id, r.peptideSeq, r.peptideModSeq, r.precursorCharge, r.precursorMZ, r.retentionTime, '
        'r.numPeaks, p.peakIntensity FROM RefSpectra r JOIN RefSpectraPeaks p ON p.RefSpectraID = r.id ORDER BY r.id')
    annotations = con.cursor().execute(
        'SELECT RefSpectraID, peakIndex, name, charge, mzTheoretical FROM RefSpectraPeakAnnotations ORDER BY RefSpectraID, peakIndex')
    pending = annotations.fetchone()
    n_prec = n_rows = skipped = 0
    with open(out_tsv, 'w', newline='\n') as f:
        f.write('\t'.join(EXPORT_COLUMNS) + '\n')
        for sid, seq, modseq, z, mz, rt, n, blob in spectra:
            ann = []
            while pending is not None and pending[0] < sid:
                pending = annotations.fetchone()
            while pending is not None and pending[0] == sid:
                ann.append(pending)
                pending = annotations.fetchone()
            if sid in decoy_ids:
                continue
            raw = blob if len(blob) == n * 4 else zlib.decompress(blob)
            intensity = struct.unpack(f'<{n}f', raw)
            top = max(intensity) or 1.0
            prefix = '\t'.join((repr(mz), unimod(modseq), seq, str(z), repr(rt), ';'.join(proteins.get(sid, []))))
            rows = 0
            for _, idx, name, fz, fmz in ann:
                m = FRAGMENT.match(name or '')
                if not m:
                    skipped += 1
                    continue
                loss = m.group(3) or 'noloss'
                f.write(f'{prefix}\t{fmz!r}\t{intensity[idx] / top:.6g}\t{m.group(1)}\t{m.group(2)}\t{fz}\t{loss}\t0\n')
                rows += 1
            n_prec += rows > 0
            n_rows += rows
    con.close()
    print(f'{n_prec} target precursors, {n_rows} fragment rows -> {out_tsv}; '
          f'{len(decoy_ids)} decoys left out; {skipped} unannotated peaks skipped')


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == 'fasta':
        fasta(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == 'convert':
        convert(*sys.argv[2:])
    elif len(sys.argv) == 4 and sys.argv[1] == 'export':
        export(*sys.argv[2:])
    else:
        sys.exit(__doc__)
