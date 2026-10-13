"""Regenerate pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/RegressionSubset.zip.

The committed inputs of regression.ps1 -Dataset StellarSubset and of TestRegressionSubset, which
runs it on every commit: a subset of the Stellar _21 training export the full regression fine-tunes
on (carafesharp-export-v2), and a subset of the library FASTA and pairing manifest it predicts
(carafesharp-testfiles-v1). Each kept part is a whole unit of the source:
  * export: every row of the peptide forms whose 64-bit FNV-1a hash of modified_sequence, shifted
    right 32 bits, is 0 modulo --export-modulus (all charges of a kept form, every column, the
    footer kept, with osprey.training_export.rows and the parity counts set to the kept rows);
  * library: the pair groups whose peptide_pair_index is 0 modulo --pairing-modulus, with all their
    members, and the FASTA records of their sequences, written as regression.ps1 writes its subset.

Usage:
  python build_regression_subset.py --data-root D:/Users/<you>/Downloads/Perftests
      --out-zip C:/.../pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/RegressionSubset.zip
The defaults are the parameters of the committed zip. The output is byte-identical for the same
inputs and pyarrow version.
"""
import argparse
import hashlib
import io
import os
import sys
import zipfile

import pyarrow as pa
import pyarrow.parquet as pq

RUN = 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21'
EXPORT = 'carafesharp-export-v2/stellar/' + RUN + '.training.parquet'
FASTA = 'carafesharp-testfiles-v1/stellar/carafe-osprey-entrapment/osprey_library_db_peptides.fasta'
PAIRING = 'carafesharp-testfiles-v1/stellar/carafe-osprey-entrapment/osprey_library_db_pairing.tsv'
ZIP_TIME = (1980, 1, 1, 0, 0, 0)

FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211


def fnv_key(text):
    h = FNV_OFFSET
    for b in text.encode('utf-8'):
        h ^= b
        h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h >> 32


def subset_export(path, modulus):
    table = pq.read_table(path)
    keep = pa.array([fnv_key(s) % modulus == 0 for s in table.column('modified_sequence').to_pylist()])
    subset = table.filter(keep)
    metadata = dict(table.schema.metadata or {})
    rows = str(subset.num_rows).encode()
    metadata[b'osprey.training_export.rows'] = rows
    for key in (b'osprey.training_export.mp_cosine_parity', b'osprey.training_export.mp_cosine_parity_fitted'):
        if key in metadata:
            metadata[key] = rows + b'/' + rows
    metadata[b'carafesharp.subset'] = ('the rows of the peptide forms whose FNV-1a key of modified_sequence is 0 modulo %d, '
                                       'of %d rows' % (modulus, table.num_rows)).encode()
    subset = subset.replace_schema_metadata(metadata)
    buffer = io.BytesIO()
    pq.write_table(subset, buffer, compression='zstd', compression_level=19)
    return buffer.getvalue(), subset.num_rows, len(set(subset.column('modified_sequence').to_pylist())), table.num_rows


def subset_pairing(path, modulus):
    """The header and the rows whose peptide_pair_index is 0 modulo the modulus (regression.ps1 Write-SubsetPairing)."""
    out = []
    sequences = set()
    groups = set()
    with open(path, encoding='utf-8', newline='') as f:
        header = f.readline().rstrip('\r\n')
        names = [n.strip().lower() for n in header.split('\t')]
        seq_col, pair_col = names.index('sequence'), names.index('peptide_pair_index')
        out.append(header + '\n')
        for line in f:
            line = line.rstrip('\r\n')
            if not line:
                continue
            cells = line.split('\t')
            index = int(cells[pair_col].strip())
            if index % modulus == 0:
                out.append(line + '\n')
                sequences.add(cells[seq_col].strip())
                groups.add(index)
    return ''.join(out).encode('utf-8'), sequences, len(groups), len(out) - 1


def subset_fasta(path, sequences):
    """The records of the kept sequences, as '>' + header + '\\n' + sequence + '\\n' (regression.ps1 Write-SubsetFasta)."""
    out = []
    header, parts = None, []

    def flush():
        if header is not None:
            sequence = ''.join(parts)
            if sequence in sequences:
                out.append('>%s\n%s\n' % (header, sequence))

    with open(path, encoding='utf-8') as f:
        for line in f:
            trimmed = line.strip()
            if trimmed.startswith('>'):
                flush()
                header, parts = trimmed[1:], []
            else:
                parts.append(''.join(trimmed.split()))
    flush()
    return ''.join(out).encode('utf-8'), len(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-root', required=True, help='the folder holding the extracted carafesharp-* packages')
    ap.add_argument('--out-zip', required=True)
    ap.add_argument('--export-modulus', type=int, default=15)
    ap.add_argument('--pairing-modulus', type=int, default=500)
    a = ap.parse_args()

    export_bytes, rows, forms, source_rows = subset_export(os.path.join(a.data_root, EXPORT), a.export_modulus)
    pairing_bytes, sequences, groups, pairing_rows = subset_pairing(os.path.join(a.data_root, PAIRING), a.pairing_modulus)
    fasta_bytes, records = subset_fasta(os.path.join(a.data_root, FASTA), sequences)
    if records < len(sequences):
        sys.exit('%s has no record for %d of the subset sequences' % (FASTA, len(sequences) - records))

    readme = (
        'CarafeSharp regression subset (built by ai/scripts/CarafeSharp/SubsetData/build_regression_subset.py)\n\n'
        'stellar/%s.training.parquet\n'
        '  %d of the %d rows of %s (%d peptide forms): every row of the forms whose 64-bit FNV-1a hash of\n'
        '  modified_sequence, shifted right 32 bits, is 0 modulo %d. All columns and the footer are kept;\n'
        '  osprey.training_export.rows and the mp_cosine_parity counts are the kept rows.\n'
        '  Source SHA-256: %s\n\n'
        'library_subset_pairing.tsv, library_subset_peptides.fasta\n'
        '  The %d pair groups of %s whose peptide_pair_index is 0 modulo %d (%d rows), and the %d\n'
        '  records of %s holding their sequences.\n'
        % (RUN, rows, source_rows, EXPORT, forms, a.export_modulus,
           sha256_file(os.path.join(a.data_root, EXPORT)),
           groups, PAIRING, a.pairing_modulus, pairing_rows, records, FASTA))

    entries = [
        ('README.txt', readme.encode('utf-8')),
        ('library_subset_pairing.tsv', pairing_bytes),
        ('library_subset_peptides.fasta', fasta_bytes),
        ('stellar/%s.training.parquet' % RUN, export_bytes),
    ]
    with zipfile.ZipFile(a.out_zip, 'w') as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data, compresslevel=9)
    print('%s: %d bytes; export %d rows (%d forms) of %d, %d bytes; %d pair groups, %d pairing rows, %d FASTA records'
          % (a.out_zip, os.path.getsize(a.out_zip), rows, forms, source_rows, len(export_bytes), groups, pairing_rows, records))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


if __name__ == '__main__':
    main()
