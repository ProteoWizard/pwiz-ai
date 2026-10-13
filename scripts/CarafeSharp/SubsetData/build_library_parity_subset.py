"""Regenerate pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/LibraryParitySubset.zip.

The committed inputs of LibraryParityTest.TestLibraryParitySubset and of
CarafeParityTest.TestPretrainedPredictionsMatchCarafeSubset, which run on every commit: a
carafesharp-testfiles-v1 folder laid out as the full package, holding a fraction of five Carafe
reference runs. Nothing is rerun through Carafe: every file is a filtered copy of the package's.

What is kept, per run (the defaults are the committed strides):
  stellar/carafe-osprey-entrapment/osprey_initial_library   (--stellar-initial-stride 500)
  stellar/carafe-osprey-entrapment/osprey_new_library       (--stellar-finetuned-stride 1000, no models)
  library-references/m3/ref/nocut-every50                   (--nocut-stride 25, with its .blib)
  library-references/m3/ref/trypsin-proteins                (--trypsin-stride 8, with its .blib)
  library-references/carafe_main_varmod                     (--varmod-stride 30, with its .blib)

Each run's FASTA records are grouped so that no peptide, protein ID or decoy pair crosses a
group: records are joined when they yield the same peptide (for NoCut, the record's sequence and
its M-clipped copy; for an enzyme, every record holding the peptide as a substring, which can only
over-join), when the library TSV's ProteinID names them together, and when the pairing TSV beside
the FASTA puts their sequences in one peptide_pair_index group (target, decoy and the entrapment
pair together). The groups, in the order of their first record, are kept when their ordinal is 0
modulo the run's stride. Then every file keeps exactly what the kept records yield:
  * the FASTA: the kept records, byte for byte;
  * peptide_forms_k, k_rt_pred: the rows whose peptide the kept records yield;
  * k_ms2_df: the same rows, with frag_start_idx/frag_stop_idx renumbered over the kept rows, and
    k_ms2_mz_df / k_ms2_pred: the fragment rows of the kept rows, in the same order;
  * the library TSV: the lines of the kept peptides, unchanged (each kept line's ProteinID is
    checked to name only kept records, and each dropped line's none);
  * the .blib: the RefSpectra of the kept peptides and the rows of every table keyed to them,
    LibInfo.numSpecs set to the count, then VACUUM;
  * parameter.txt (and the fine-tuned run's meta.json and model_evaluation_metrics.json), unchanged,
    so the tests relocate the paths Carafe recorded into this package as they do in the full one;
  * stellar/carafe-osprey-entrapment/osprey_train_db_pairing.tsv, the -pairing_manifest of
    nocut-every50: every pair group holding a kept sequence, and every other group holding one of
    their sequences, so the decoy-pair gate sees each kept sequence exactly as in the full manifest.
The second Stellar run (carafe-osprey) is left out: its initial-library predictions are the same
files, and the tests skip an item path a subset lacks. Fine-tuned models (16 MB) are left out, so
the fine-tuned run serves the peptide-form, fragment m/z and assembly checks, not prediction.

README.txt describes the subset, and MANIFEST.sha256 (the zip's last entry) lists every file as
the full package's does.

Usage:
  python build_library_parity_subset.py --data-root D:/Users/<you>/Downloads/Perftests
      --out-zip C:/.../pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/LibraryParitySubset.zip
The defaults are the parameters of the committed zip. The output is byte-identical for the same
inputs and pyarrow and SQLite versions.
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import zipfile

import pyarrow as pa
import pyarrow.parquet as pq

PACKAGE = 'carafesharp-testfiles-v1'
STELLAR = 'stellar/carafe-osprey-entrapment'
TRAIN_PAIRING = STELLAR + '/osprey_train_db_pairing.tsv'
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
TSV_HEADER = b'ModifiedPeptide\tStrippedPeptide\tPrecursorMz\tPrecursorCharge\tTr_recalibrated\tProteinID\tDecoy\t'
BLIB = 'carafe_spectral_library.blib'
# Tables keyed to RefSpectra.id, and the column holding it.
BLIB_KEYED_TABLES = [('RefSpectraPeaks', 'RefSpectraID'), ('Modifications', 'RefSpectraID'),
                     ('RetentionTimes', 'RefSpectraID'), ('RefSpectraPeakAnnotations', 'RefSpectraID'),
                     ('DecoyPairs', 'RefSpectraID')]


class Run(object):
    def __init__(self, name, folder, fasta, stride_arg, no_cut, tsv, pairing=None, extras=(), blib=False):
        self.name = name
        self.folder = folder
        self.fasta = fasta
        self.stride_arg = stride_arg
        self.no_cut = no_cut
        self.tsv = tsv
        self.pairing = pairing
        self.extras = list(extras)
        self.blib = blib


RUNS = [
    Run('Stellar pretrained', STELLAR + '/osprey_initial_library', STELLAR + '/osprey_train_db_peptides.fasta',
        'stellar_initial_stride', True, 'carafe_spectral_library.tsv', pairing=TRAIN_PAIRING),
    Run('Stellar fine-tuned', STELLAR + '/osprey_new_library', STELLAR + '/osprey_library_db_peptides.fasta',
        'stellar_finetuned_stride', True, 'stellar-paired-entrapment-carafe_library.tsv',
        pairing=STELLAR + '/osprey_library_db_pairing.tsv', extras=['meta.json', 'model_evaluation_metrics.json']),
    Run('m3 NoCut every-50', 'library-references/m3/ref/nocut-every50', 'library-references/m3/fixtures/peptides_every50.fasta',
        'nocut_stride', True, 'carafe_spectral_library.tsv', pairing=TRAIN_PAIRING, blib=True),
    Run('m3 trypsin proteins', 'library-references/m3/ref/trypsin-proteins', 'library-references/m3/fixtures/proteins300.fasta',
        'trypsin_stride', False, 'carafe_spectral_library.tsv', blib=True),
    Run('variable modifications', 'library-references/carafe_main_varmod', 'library-references/hela-300.fasta',
        'varmod_stride', False, 'carafe_spectral_library.tsv', blib=True),
]


class UnionFind(object):
    def __init__(self, n):
        self.parent = list(range(n))

    def find(self, i):
        root = i
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[i] != root:
            self.parent[i], i = root, self.parent[i]
        return root

    def union(self, items):
        items = list(items)
        for other in items[1:]:
            a, b = self.find(items[0]), self.find(other)
            if a != b:
                # The smaller index is the root, so a group's root is its first record.
                self.parent[max(a, b)] = min(a, b)


def read_fasta(path):
    """The records as (raw bytes, accession, upper-case sequence), in file order."""
    records = []
    with open(path, 'rb') as f:
        data = f.read()
    starts = _record_starts(data)
    starts.append(len(data))
    for a, b in zip(starts, starts[1:]):
        raw = data[a:b]
        lines = raw.decode('utf-8').splitlines()
        header = lines[0][1:].strip()
        sequence = ''.join(''.join(l.split()) for l in lines[1:]).upper()
        records.append((raw, header.split()[0] if header else '', sequence))
    return records


def _record_starts(data):
    starts = [0] if data.startswith(b'>') else []
    i = data.find(b'\n>')
    while i >= 0:
        starts.append(i + 1)
        i = data.find(b'\n>', i + 1)
    return starts


def numbered(folder, prefix, suffix):
    found = []
    for name in os.listdir(folder):
        if name.startswith(prefix) and name.endswith(suffix) and name[len(prefix):len(name) - len(suffix)].isdigit():
            found.append((int(name[len(prefix):len(name) - len(suffix)]), name))
    return [name for _, name in sorted(found)]


def batches(folder):
    found = []
    for name in os.listdir(folder):
        head = name.split('_')[0]
        if name.endswith('_ms2_df.parquet') and head.isdigit():
            found.append(int(head))
    return sorted(found)


class RunSubset(object):
    """Selects one run's kept records and writes its filtered files."""

    def __init__(self, root, run, stride):
        self.root = root
        self.run = run
        self.stride = stride
        self.folder = os.path.join(root, run.folder)
        self.records = read_fasta(os.path.join(root, run.fasta))
        self.by_sequence = {}
        self.by_accession = {}
        for i, (_, accession, sequence) in enumerate(self.records):
            self.by_sequence.setdefault(sequence, []).append(i)
            # A header can join accessions with ';' as ProteinID does, so each part names the record.
            for part in accession.split(';'):
                self.by_accession.setdefault(part, []).append(i)
        self.groups = UnionFind(len(self.records))
        self._hosts = {}
        self._parquet_sequences = set()
        self.kept = None

    def hosts(self, peptide):
        """The records that yield the peptide (for an enzyme, every record holding it, a superset)."""
        found = self._hosts.get(peptide)
        if found is None:
            if self.run.no_cut:
                found = self.by_sequence.get(peptide, []) + self.by_sequence.get('M' + peptide, [])
            else:
                found = [i for i, record in enumerate(self.records) if peptide in record[2]]
            self._hosts[peptide] = found
        return found

    def select(self):
        for name in self._parquet_files():
            table = pq.read_table(os.path.join(self.folder, name), columns=['sequence'])
            self._parquet_sequences.update(s for s in table.column('sequence').to_pylist() if s is not None)
        for peptide in sorted(self._parquet_sequences):
            hosts = self.hosts(peptide)
            if not hosts:
                sys.exit('%s: no record of %s yields %s' % (self.run.name, self.run.fasta, peptide))
            self.groups.union(hosts)
        if not self.run.no_cut:
            # Small TSVs: join the records each ProteinID names together, and those yielding its peptide.
            for peptide, protein_id in self._tsv_precursors():
                self.groups.union(self.hosts(peptide) + [i for a in protein_id.split(';') for i in self.by_accession.get(a, [])])
        if self.run.pairing:
            by_pair = {}
            for sequence, index in read_pairing(os.path.join(self.root, self.run.pairing))[1]:
                by_pair.setdefault(index, []).extend(self.by_sequence.get(sequence, []))
            for members in by_pair.values():
                if members:
                    self.groups.union(members)
        roots = sorted(set(self.groups.find(i) for i in range(len(self.records))))
        kept_roots = set(r for k, r in enumerate(roots) if k % self.stride == 0)
        self.kept = [self.groups.find(i) in kept_roots for i in range(len(self.records))]
        self.group_count, self.kept_group_count = len(roots), len(kept_roots)
        self.kept_accessions = set(p for r, k in zip(self.records, self.kept) if k for p in r[1].split(';'))
        self.kept_sequences = set(r[2] for r, k in zip(self.records, self.kept) if k)

    def is_kept(self, peptide):
        hosts = self.hosts(peptide)
        if not hosts:
            sys.exit('%s: no record of %s yields %s' % (self.run.name, self.run.fasta, peptide))
        kept = set(self.kept[i] for i in hosts)
        if len(kept) != 1:
            sys.exit('%s: %s is yielded by kept and dropped records' % (self.run.name, peptide))
        return kept.pop()

    def fasta_bytes(self):
        return b''.join(r[0] for r, k in zip(self.records, self.kept) if k)

    def _parquet_files(self):
        names = numbered(self.folder, 'peptide_forms_', '.parquet')
        for batch in batches(self.folder):
            names.append('%d_ms2_df.parquet' % batch)
            names.append('%d_rt_pred.parquet' % batch)
        return names

    def _tsv_precursors(self):
        seen = set()
        with open(os.path.join(self.folder, self.run.tsv), 'rb') as f:
            f.readline()
            for line in f:
                cells = line.split(b'\t', 6)
                pair = (cells[1].decode('ascii'), cells[5].decode('ascii'))
                if pair not in seen:
                    seen.add(pair)
                    yield pair

    def parquet_entries(self):
        """(name, bytes, kept rows, source rows) of every parquet file of the run."""
        out = []
        for name in numbered(self.folder, 'peptide_forms_', '.parquet'):
            out.append((name,) + self._filter_rows(os.path.join(self.folder, name)))
        for batch in batches(self.folder):
            out.extend(self._filter_batch(batch))
            out.append(('%d_rt_pred.parquet' % batch,) + self._filter_rows(os.path.join(self.folder, '%d_rt_pred.parquet' % batch)))
        return out

    def _mask(self, table):
        return pa.array([s is not None and self.is_kept(s) for s in table.column('sequence').to_pylist()], pa.bool_())

    def _filter_rows(self, path):
        table = pq.read_table(path)
        if table.num_rows == 0:
            return read_bytes(path), 0, 0
        subset = table.filter(self._mask(table))
        return write_parquet(subset, table), subset.num_rows, table.num_rows

    def _filter_batch(self, batch):
        names = ['%d_ms2_df.parquet' % batch, '%d_ms2_mz_df.parquet' % batch, '%d_ms2_pred.parquet' % batch]
        paths = [os.path.join(self.folder, n) for n in names]
        frame = pq.read_table(paths[0])
        if frame.num_rows == 0:
            return [(n, read_bytes(p), 0, 0) for n, p in zip(names, paths)]
        subset = frame.filter(self._mask(frame))
        starts = subset.column('frag_start_idx').to_pylist()
        stops = subset.column('frag_stop_idx').to_pylist()
        fragment_rows, new_starts, new_stops = [], [], []
        for start, stop in zip(starts, stops):
            new_starts.append(len(fragment_rows))
            fragment_rows.extend(range(start, stop))
            new_stops.append(len(fragment_rows))
        for column, values in (('frag_start_idx', new_starts), ('frag_stop_idx', new_stops)):
            index = subset.schema.get_field_index(column)
            subset = subset.set_column(index, subset.schema.field(index), pa.array(values, subset.schema.field(index).type))
        out = [(names[0], write_parquet(subset, frame), subset.num_rows, frame.num_rows)]
        take = pa.array(fragment_rows, pa.int64())
        for name, path in zip(names[1:], paths[1:]):
            fragments = pq.read_table(path)
            kept = fragments.take(take)
            out.append((name, write_parquet(kept, fragments), kept.num_rows, fragments.num_rows))
        return out

    def tsv_bytes(self):
        """The kept peptides' lines, unchanged; each kept line's ProteinID names only kept records, each dropped line's none."""
        out = io.BytesIO()
        lines = kept_precursors = 0
        last = None
        with open(os.path.join(self.folder, self.run.tsv), 'rb') as f:
            header = f.readline()
            if not header.startswith(TSV_HEADER):
                sys.exit('%s: unexpected header in %s' % (self.run.name, self.run.tsv))
            out.write(header)
            decided = {}
            for line in f:
                cells = line.split(b'\t', 6)
                peptide = cells[1]
                keep = decided.get(peptide)
                if keep is None:
                    keep = decided[peptide] = self.is_kept(peptide.decode('ascii'))
                key = (cells[0], cells[3], cells[5])
                if key != last:
                    last = key
                    named = [a in self.kept_accessions for a in cells[5].decode('ascii').split(';')]
                    if (keep and not all(named)) or (not keep and any(named)):
                        sys.exit('%s: ProteinID %s of %s crosses the kept records' % (self.run.name, cells[5], peptide))
                    if keep:
                        kept_precursors += 1
                if keep:
                    out.write(line)
                    lines += 1
        self.tsv_precursors, self.tsv_lines = kept_precursors, lines
        return out.getvalue()

    def blib_bytes(self, scratch):
        path = os.path.join(scratch, self.run.name.replace(' ', '_') + '.blib')
        shutil.copyfile(os.path.join(self.folder, BLIB), path)
        connection = sqlite3.connect(path)
        try:
            ids = [i for i, peptide in connection.execute('SELECT id, peptideSeq FROM RefSpectra ORDER BY id')
                   if not self.is_kept(peptide)]
            connection.execute('CREATE TEMP TABLE Dropped (id INTEGER PRIMARY KEY)')
            connection.executemany('INSERT INTO Dropped VALUES (?)', [(i,) for i in ids])
            tables = set(r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'"))
            for table, column in BLIB_KEYED_TABLES:
                if table in tables:
                    connection.execute('DELETE FROM %s WHERE %s IN (SELECT id FROM Dropped)' % (table, column))
            connection.execute('DELETE FROM RefSpectra WHERE id IN (SELECT id FROM Dropped)')
            self.blib_spectra = connection.execute('SELECT COUNT(*) FROM RefSpectra').fetchone()[0]
            connection.execute('UPDATE LibInfo SET numSpecs = ?', (self.blib_spectra,))
            connection.execute('DROP TABLE Dropped')
            connection.commit()
            connection.execute('VACUUM')
        finally:
            connection.close()
        return read_bytes(path)


def read_pairing(path):
    """The header line and the (sequence, peptide_pair_index) of each row, with the raw lines."""
    rows = []
    with open(path, 'rb') as f:
        header = f.readline()
        names = [n.strip().lower() for n in header.decode('utf-8').rstrip('\r\n').split('\t')]
        seq_col, pair_col = names.index('sequence'), names.index('peptide_pair_index')
        for line in f:
            if not line.strip():
                continue
            cells = line.decode('utf-8').rstrip('\r\n').split('\t')
            rows.append((cells[seq_col].strip().upper(), int(cells[pair_col].strip()), line))
    return header, [(s, i) for s, i, _ in rows], rows


def subset_pairing(path, sequences):
    """Every group holding one of the sequences, and every group holding one of those groups' sequences."""
    header, _, rows = read_pairing(path)
    first = set(i for s, i, _ in rows if s in sequences)
    reached = set(s for s, i, _ in rows if i in first)
    groups = set(i for s, i, _ in rows if s in reached)
    kept = [line for s, i, line in rows if i in groups]
    return header + b''.join(kept), len(groups), len(kept)


def write_parquet(table, source):
    """The table as parquet (zstd), with the source's schema metadata and the pandas row range set to its rows."""
    metadata = dict(source.schema.metadata or {})
    if b'pandas' in metadata:
        pandas = json.loads(metadata[b'pandas'])
        for index in pandas.get('index_columns', []):
            if isinstance(index, dict) and index.get('kind') == 'range':
                index['stop'] = table.num_rows
        metadata[b'pandas'] = json.dumps(pandas).encode('utf-8')
    table = table.replace_schema_metadata(metadata)
    buffer = io.BytesIO()
    pq.write_table(table, buffer, compression='zstd', compression_level=19)
    return buffer.getvalue()


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def manifest_key(path):
    """The full package's MANIFEST order: in each folder its files, then its subfolders, by name."""
    parts = path.split('/')
    return [(1, p) for p in parts[:-1]] + [(0, parts[-1])]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-root', required=True, help='the folder holding the extracted carafesharp-testfiles-v1 package')
    ap.add_argument('--out-zip', required=True)
    ap.add_argument('--stellar-initial-stride', type=int, default=500)
    ap.add_argument('--stellar-finetuned-stride', type=int, default=1000)
    ap.add_argument('--nocut-stride', type=int, default=25)
    ap.add_argument('--trypsin-stride', type=int, default=8)
    ap.add_argument('--varmod-stride', type=int, default=30)
    a = ap.parse_args()
    root = os.path.join(a.data_root, PACKAGE)

    files = {}
    notes = []
    nocut_sequences = None
    scratch = tempfile.mkdtemp(prefix='library_parity_subset_')
    try:
        for run in RUNS:
            stride = getattr(a, run.stride_arg)
            subset = RunSubset(root, run, stride)
            subset.select()
            if run.fasta in files:
                sys.exit('%s is the FASTA of two runs' % run.fasta)
            files[run.fasta] = subset.fasta_bytes()
            kept_records = sum(subset.kept)
            sizes = {}
            for name, data, rows, source_rows in subset.parquet_entries():
                files[run.folder + '/' + name] = data
                sizes[name] = (rows, source_rows)
            files[run.folder + '/' + run.tsv] = subset.tsv_bytes()
            files[run.folder + '/parameter.txt'] = read_bytes(os.path.join(subset.folder, 'parameter.txt'))
            for name in run.extras:
                files[run.folder + '/' + name] = read_bytes(os.path.join(subset.folder, name))
            blib_note = ''
            if run.blib:
                files[run.folder + '/' + BLIB] = subset.blib_bytes(scratch)
                blib_note = ', %d .blib spectra' % subset.blib_spectra
            if run.pairing == TRAIN_PAIRING and run.blib:
                nocut_sequences = subset.kept_sequences
            forms = sum(sizes[n][0] for n in sizes if n.startswith('peptide_forms_'))
            forms_source = sum(sizes[n][1] for n in sizes if n.startswith('peptide_forms_'))
            notes.append('%s\n  %s, %s: the record groups whose ordinal is 0 modulo %d (%d of %d groups, %d of %d records);\n'
                         '  %d of %d peptide_forms rows, %d TSV precursors (%d lines)%s.\n'
                         % (run.folder, run.name, run.fasta, stride, subset.kept_group_count, subset.group_count,
                            kept_records, len(subset.records), forms, forms_source, subset.tsv_precursors, subset.tsv_lines,
                            blib_note))
            print('%s: %d of %d groups, %d of %d records, %d of %d peptide_forms rows, %d TSV precursors%s'
                  % (run.name, subset.kept_group_count, subset.group_count, kept_records, len(subset.records),
                     forms, forms_source, subset.tsv_precursors, blib_note))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    pairing_bytes, groups, rows = subset_pairing(os.path.join(root, TRAIN_PAIRING), nocut_sequences)
    files[TRAIN_PAIRING] = pairing_bytes
    notes.append('%s\n  The -pairing_manifest of nocut-every50: the %d pair groups (%d rows) holding its kept sequences,\n'
                 '  or a sequence of such a group.\n' % (TRAIN_PAIRING, groups, rows))

    readme = ('CarafeSharp test data: LibraryParitySubset, a subset of carafesharp-testfiles-v1\n'
              '(built by ai/scripts/CarafeSharp/SubsetData/build_library_parity_subset.py)\n\n'
              'Laid out as the full package, with the files LibraryParityTest and CarafeParityTest read for\n'
              'a fraction of the FASTA records of each run below. Records are grouped so that no peptide,\n'
              'ProteinID or decoy pair crosses groups, and every file keeps exactly what the kept records\n'
              'yield (k_ms2_df fragment indexes renumbered). parameter.txt files are Carafe\'s, unchanged.\n'
              'The fine-tuned run has no models; the second Stellar run is left out.\n\n' + '\n'.join(notes))
    files['README.txt'] = readme.encode('utf-8')

    names = sorted(files, key=manifest_key)
    manifest = ''.join('%s  %s\n' % (hashlib.sha256(files[n]).hexdigest(), n) for n in names).encode('ascii')
    entries = [(PACKAGE + '/' + n, files[n]) for n in names] + [(PACKAGE + '/MANIFEST.sha256', manifest)]
    with zipfile.ZipFile(a.out_zip, 'w') as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data, compresslevel=9)
    print('%s: %d bytes, %d files' % (a.out_zip, os.path.getsize(a.out_zip), len(entries)))
    for name, data in entries:
        print('  %9d  %s' % (len(data), name))


if __name__ == '__main__':
    main()
