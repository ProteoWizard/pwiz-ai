"""Regenerate pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/TrainingParitySubset.zip.

The committed data of TestFineTuneMatchesCarafeSubset and TestMaskingAgreesWithCarafeSubset, which
run the checks of CarafeFineTuneParityTest.TestFineTuneMatchesCarafe and
OspreyMaskingParityTest.TestMaskingAgreesWithCarafe on every commit. The zip holds two package
folders laid out as the full packages are, each with its own README.txt and MANIFEST.sha256:

carafesharp-testfiles-v1/stellar/carafe-osprey-entrapment/osprey_new_library (Carafe's fine-tuning
folder; the no-entrapment copy has byte-identical training tables, so it is left out):
  * psm_pdv.txt, meta.json, parameter.txt, model_evaluation_metrics.json, rt_test.tsv and
    test_true_intensity.tsv verbatim. Every training row is kept, because Carafe's train/test
    split (TrainingSplit) samples from the whole table and the test checks that split.
  * fragment_intensity_df.tsv: every row, the intensities kept only for Carafe's held-out MS2
    spectra (Carafe's split, TrainingSplit.cs, ported here) and 0.0 elsewhere.
    The default test reads intensities only of held-out spectra (to match test_true_intensity.tsv
    and score the pretrained model); the builder checks the kept values are test_true_intensity.tsv
    in order. A fine-tune on this table would train on zeros, so the subset never runs
    CARAFESHARP_FINETUNE_FULL.
  * fragment_intensity_valid.tsv: every row, the masking counts kept for the held-out spectra
    (pretrained scoring masks with them) and for the spectra the masking test compares (sequence
    sampled, below), 0 elsewhere.
  * rt_train_data.tsv: every row, rt_norm kept for the rows of Carafe's held-out RT forms (the
    sequence/mods/mod_sites of rt_test.tsv) and 0.0 elsewhere; the rt and y columns, which nothing
    reads, are 0.0 too. The pretrained RT score reads only held-out forms.
  * ../osprey_library_db_peptides.fasta: an empty stand-in. parameter.txt's -db names it and the
    test resolves it inside the package, but nothing reads it.

carafesharp-export-v1/stellar/<run>.training.parquet: the rows whose 64-bit FNV-1a hash of the
  stripped sequence, shifted right 32 bits, is 0 modulo --sequence-modulus, without the xic_rts and
  xic_intensities columns (which CarafeSharp never reads). The footer is kept, with
  osprey.training_export.rows and the mp_cosine_parity counts set to the kept rows, plus
  carafesharp.subset (the rule) and carafesharp.subset.sequence_modulus, which the masking test
  reads to compare only Carafe's spectra of the same sequences.

Usage:
  python build_training_parity_subset.py --data-root D:/Users/<you>/Downloads/Perftests
      --out-zip C:/.../pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/TrainingParitySubset.zip
The defaults are the parameters of the committed zip. The output is byte-identical for the same
inputs and pyarrow version.
"""
import argparse
import csv
import hashlib
import io
import math
import os
import sys
import zipfile

import numpy
import pyarrow as pa
import pyarrow.parquet as pq

RUN = 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21'
TESTFILES = 'carafesharp-testfiles-v1'
EXPORT_PACKAGE = 'carafesharp-export-v1'
CARAFE_RUN = 'stellar/carafe-osprey-entrapment'
NEW_LIBRARY = CARAFE_RUN + '/osprey_new_library'
EXPORT = 'stellar/' + RUN + '.training.parquet'
VERBATIM = ['meta.json', 'model_evaluation_metrics.json', 'parameter.txt', 'psm_pdv.txt', 'rt_test.tsv',
            'test_true_intensity.tsv']
DATABASE_STAND_IN = CARAFE_RUN + '/osprey_library_db_peptides.fasta'
DROPPED_COLUMNS = ['xic_rts', 'xic_intensities']
ZIP_TIME = (1980, 1, 1, 0, 0, 0)

# TrainingSplit.cs, Carafe's split of its training rows.
SAMPLING_SEED = 1337
MAX_TEST = 1000
TOP_N_MODS = 10
ROWS_PER_MOD = 50

FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211


def fnv_key(text):
    h = FNV_OFFSET
    for b in text.encode('utf-8'):
        h ^= b
        h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h >> 32


def is_sampled(sequence, modulus):
    return fnv_key(sequence) % modulus == 0


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def split_lines(data):
    """The lines of a text file and its line ending, which the rewritten files keep."""
    eol = b'\r\n' if b'\r\n' in data else b'\n'
    lines = data.split(eol)
    if lines and lines[-1] == b'':
        lines.pop()
    return lines, eol


def join_lines(lines, eol):
    return eol.join(lines) + eol


def held_out_ms2_ranges(spectra):
    """Carafe's held-out MS2 spectra as (frag_start_idx, frag_stop_idx), in test order: TrainingSplit.cs, ported."""
    n = len(spectra)
    test_count = max(1, min(MAX_TEST, int(math.ceil(n * 0.1)) - 10))
    train_count = n - test_count
    sequences = [s for s, _, _, _ in spectra]
    mods = [m for _, m, _, _ in spectra]
    train = list(sample_rows(list(range(n)), train_count))
    if train_count < n:
        for mod in top_modifications(mods):
            train += sample_rows([i for i in range(n) if mod in mods[i]], ROWS_PER_MOD)
    train_sequences = set(sequences[i] for i in train)
    candidates = [i for i in range(n) if sequences[i] not in train_sequences]
    if len(candidates) > test_count:
        test = sample_rows(candidates, test_count)
    elif not candidates:
        test = list(range(n))
    else:
        test = candidates
    return [(spectra[i][2], spectra[i][3]) for i in test]


def sample_rows(rows, count):
    """pandas df.sample(count, random_state=1337): numpy's legacy permutation, first count."""
    if count >= len(rows):
        return rows
    order = numpy.random.RandomState(SAMPLING_SEED).permutation(len(rows))[:count]
    return [rows[i] for i in order]


def top_modifications(mods):
    """Carafe's count_mods: the 10 most frequent modifications, ties in order of first appearance."""
    counts, order = {}, []
    for text in mods:
        for mod in dict.fromkeys(m for m in text.split(';') if m):
            parts = mod.split('->')
            if len(parts) == 2 and len(parts[0]) == 3 and len(parts[1]) == 5:
                continue
            if mod not in counts:
                counts[mod] = 0
                order.append(mod)
            counts[mod] += 1
    return sorted(order, key=lambda m: (-counts[m], order.index(m)))[:TOP_N_MODS]


def psm_ranges(folder):
    """Each training spectrum's (sequence, mods, frag_start_idx, frag_stop_idx) from psm_pdv.txt."""
    with open(os.path.join(folder, 'psm_pdv.txt'), encoding='utf-8', newline='') as f:
        return [(r['peptide'], r['mods'] or '', int(r['frag_start_idx']), int(r['frag_stop_idx']))
                for r in csv.DictReader(f, delimiter='\t', quoting=csv.QUOTE_NONE)]


def keep_fragment_rows(path, keep, zero):
    """The fragment table with the rows not in keep set to zero in every column."""
    lines, eol = split_lines(read_bytes(path))
    columns = len(lines[0].split(b'\t'))
    zero_line = b'\t'.join([zero] * columns)
    out = [lines[0]] + [line if i in keep else zero_line for i, line in enumerate(lines[1:])]
    return join_lines(out, eol), len(lines) - 1


def check_held_out(intensity_bytes, held_out, true_path):
    """Fails unless the kept intensities of the held-out spectra, in test order, are test_true_intensity.tsv."""
    lines, _ = split_lines(intensity_bytes)
    rows = lines[1:]
    ours = [float(v) for start, stop in held_out for line in rows[start:stop] for v in line.split(b'\t')[:4]]
    true_lines, _ = split_lines(read_bytes(true_path))
    theirs = [float(v) for line in true_lines[1:] if line for v in line.split(b'\t')[:4]]
    if ours != theirs:
        sys.exit('The held-out spectra of the ported split are not those of test_true_intensity.tsv')


def subset_rt(folder):
    """rt_train_data.tsv with rt_norm kept for the rows of the held-out forms of rt_test.tsv, and rt, y and the other rt_norm 0.0."""
    with open(os.path.join(folder, 'rt_test.tsv'), encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f, delimiter='\t', quoting=csv.QUOTE_NONE)
        test_keys = set((r['sequence'], r['mods'] or '', r['mod_sites'] or '') for r in reader)
    lines, eol = split_lines(read_bytes(os.path.join(folder, 'rt_train_data.tsv')))
    header = lines[0].decode('utf-8').split('\t')
    seq, mods, sites = header.index('sequence'), header.index('mods'), header.index('mod_sites')
    zeroed = [header.index(c) for c in ('rt', 'y', 'rt_norm')]
    out = [lines[0]]
    found = set()
    kept = 0
    for line in lines[1:]:
        cells = line.decode('utf-8').split('\t')
        cells += [''] * (len(header) - len(cells))
        key = (cells[seq], cells[mods], cells[sites])
        for c in zeroed:
            if c != header.index('rt_norm') or key not in test_keys:
                cells[c] = '0.0'
        if key in test_keys:
            found.add(key)
            kept += 1
        out.append('\t'.join(cells).encode('utf-8'))
    if found != test_keys:
        sys.exit('%d held-out RT forms of rt_test.tsv have no row in rt_train_data.tsv' % len(test_keys - found))
    return join_lines(out, eol), kept, len(lines) - 1, len(test_keys)


def subset_export(path, modulus):
    table = pq.read_table(path)
    table = table.drop_columns([c for c in DROPPED_COLUMNS if c in table.column_names])
    keep = pa.array([is_sampled(s, modulus) for s in table.column('sequence').to_pylist()])
    subset = table.filter(keep)
    metadata = dict(table.schema.metadata or {})
    rows = str(subset.num_rows).encode()
    metadata[b'osprey.training_export.rows'] = rows
    for key in (b'osprey.training_export.mp_cosine_parity', b'osprey.training_export.mp_cosine_parity_fitted'):
        if key in metadata:
            metadata[key] = rows + b'/' + rows
    metadata[b'carafesharp.subset'] = ('the rows whose FNV-1a key of sequence is 0 modulo %d, of %d rows, without %s'
                                       % (modulus, table.num_rows, ' and '.join(DROPPED_COLUMNS))).encode()
    metadata[b'carafesharp.subset.sequence_modulus'] = str(modulus).encode()
    subset = subset.replace_schema_metadata(metadata)
    buffer = io.BytesIO()
    pq.write_table(subset, buffer, compression='zstd', compression_level=19)
    return buffer.getvalue(), subset.num_rows, table.num_rows


def manifest(entries):
    lines = ['%s  %s' % (hashlib.sha256(data).hexdigest(), name) for name, data in sorted(entries)]
    return ('\r\n'.join(lines) + '\r\n').encode('ascii')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-root', required=True, help='the folder holding the extracted carafesharp-* packages')
    ap.add_argument('--out-zip', required=True)
    ap.add_argument('--sequence-modulus', type=int, default=20)
    a = ap.parse_args()

    folder = os.path.join(a.data_root, TESTFILES, *NEW_LIBRARY.split('/'))
    spectra = psm_ranges(folder)
    held_out = held_out_ms2_ranges(spectra)
    held_out_rows = set(r for start, stop in held_out for r in range(start, stop))
    sampled_rows = set(r for sequence, _, start, stop in spectra if is_sampled(sequence, a.sequence_modulus)
                       for r in range(start, stop))
    sampled_spectra = sum(1 for sequence, _, _, _ in spectra if is_sampled(sequence, a.sequence_modulus))

    intensity_bytes, fragment_rows = keep_fragment_rows(os.path.join(folder, 'fragment_intensity_df.tsv'), held_out_rows, b'0.0')
    check_held_out(intensity_bytes, held_out, os.path.join(folder, 'test_true_intensity.tsv'))
    valid_bytes, _ = keep_fragment_rows(os.path.join(folder, 'fragment_intensity_valid.tsv'), held_out_rows | sampled_rows, b'0')
    rt_bytes, rt_kept, rt_rows, rt_forms = subset_rt(folder)

    export_path = os.path.join(a.data_root, EXPORT_PACKAGE, *EXPORT.split('/'))
    export_bytes, export_rows, export_source_rows = subset_export(export_path, a.sequence_modulus)

    testfiles = [(NEW_LIBRARY + '/' + name, read_bytes(os.path.join(folder, name))) for name in VERBATIM]
    testfiles += [
        (NEW_LIBRARY + '/fragment_intensity_df.tsv', intensity_bytes),
        (NEW_LIBRARY + '/fragment_intensity_valid.tsv', valid_bytes),
        (NEW_LIBRARY + '/rt_train_data.tsv', rt_bytes),
        (DATABASE_STAND_IN, b''),
    ]
    testfiles.append(('README.txt', (
        'CarafeSharp training parity subset of %s (built by ai/scripts/CarafeSharp/SubsetData/build_training_parity_subset.py)\r\n'
        '\r\n'
        'For TestFineTuneMatchesCarafeSubset and TestMaskingAgreesWithCarafeSubset. Only %s is kept.\r\n'
        'psm_pdv.txt, meta.json, parameter.txt, model_evaluation_metrics.json, rt_test.tsv and\r\n'
        'test_true_intensity.tsv are verbatim; the training tables keep every row (%d spectra, %d fragment\r\n'
        'rows, %d RT rows) so Carafe\'s train/test split is unchanged, but:\r\n'
        '  fragment_intensity_df.tsv  intensities only of the %d held-out spectra, 0.0 elsewhere\r\n'
        '  fragment_intensity_valid.tsv  masking counts of the held-out spectra and of the %d spectra\r\n'
        '    whose sequence is sampled (FNV-1a key modulo %d), 0 elsewhere\r\n'
        '  rt_train_data.tsv  rt_norm of the %d rows of the %d held-out forms, 0.0 elsewhere; rt, y 0.0\r\n'
        '  ../osprey_library_db_peptides.fasta  empty; parameter.txt names it, nothing reads it\r\n'
        'Do not fine-tune on it: the non-held-out spectra have no intensities.\r\n'
        % (TESTFILES, NEW_LIBRARY, len(spectra), fragment_rows, rt_rows, len(held_out), sampled_spectra,
           a.sequence_modulus, rt_kept, rt_forms)).encode('ascii')))

    exports = [(EXPORT, export_bytes), ('README.txt', (
        'CarafeSharp training parity subset of %s (built by ai/scripts/CarafeSharp/SubsetData/build_training_parity_subset.py)\r\n'
        '\r\n'
        '%s\r\n'
        '  %d of the %d rows: those whose 64-bit FNV-1a hash of sequence, shifted right 32 bits, is 0\r\n'
        '  modulo %d, without the columns %s. The footer is kept; osprey.training_export.rows and the\r\n'
        '  mp_cosine_parity counts are the kept rows, carafesharp.subset.sequence_modulus is %d.\r\n'
        '  Source SHA-256: %s\r\n'
        % (EXPORT_PACKAGE, EXPORT, export_rows, export_source_rows, a.sequence_modulus,
           ', '.join(DROPPED_COLUMNS), a.sequence_modulus, sha256_file(export_path))).encode('ascii'))]

    entries = []
    for package, files in ((TESTFILES, testfiles), (EXPORT_PACKAGE, exports)):
        files = sorted(files)
        entries += [(package + '/' + name, data) for name, data in files]
        entries.append((package + '/MANIFEST.sha256', manifest(files)))
    with zipfile.ZipFile(a.out_zip, 'w') as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data, compresslevel=9)
        sizes = [(i.filename, i.file_size, i.compress_size) for i in z.infolist()]
    for name, size, compressed in sizes:
        print('  %-100s %10d %9d' % (name, size, compressed))
    print('%s: %d bytes; %d held-out MS2 spectra, %d sampled spectra, %d held-out RT forms; export %d of %d rows'
          % (a.out_zip, os.path.getsize(a.out_zip), len(held_out), sampled_spectra, rt_forms, export_rows, export_source_rows))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


if __name__ == '__main__':
    main()
