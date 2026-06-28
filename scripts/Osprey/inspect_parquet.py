"""Quick parquet inspector for Osprey .scores.parquet files.

Reports row count, column schema, CWT-candidates population fraction,
and optionally samples a few rows.

Usage:
    python inspect_parquet.py <path.parquet> [--cwt-only] [--sample N]

Exit code: 0 always (this is a reporter, not a gate). Use -e to exit
nonzero if CWT population < 50% (matching TestCsScoringPopulatesCwtCandidates).
"""
import argparse
import struct
import sys

import pyarrow.parquet as pq


def parse_cwt_blob(blob: bytes) -> int:
    """The cwt_candidates column is a binary blob:
       u32 LE count, then count * (6 * f64 LE) records.
    Returns the candidate count, -1 if malformed."""
    if blob is None or len(blob) < 4:
        return 0
    try:
        n = struct.unpack_from('<I', blob, 0)[0]
        expected = 4 + n * 6 * 8
        if len(blob) != expected:
            return -1
        return n
    except struct.error:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('path')
    ap.add_argument('--cwt-only', action='store_true',
                    help='Skip per-column schema dump; just CWT stats')
    ap.add_argument('--sample', type=int, default=0,
                    help='Print N sample rows (after header)')
    ap.add_argument('-e', '--exit-on-empty-cwt', action='store_true',
                    help='Exit 1 if <50%% of rows have CWT candidates '
                         '(matches TestCsScoringPopulatesCwtCandidates)')
    ap.add_argument('-B', '--diff', metavar='OTHER',
                    help='Diff against another parquet; aligns rows by '
                         'entry_id, reports row-set differences and '
                         'per-column max abs diff for shared rows.')
    ap.add_argument('--tolerance', type=float, default=1e-9,
                    help='Numeric tolerance for diff mode (default: 1e-9, '
                         'much tighter than Diff-Parquet.ps1 default)')
    args = ap.parse_args()

    if args.diff:
        return run_diff(args)

    pf = pq.ParquetFile(args.path)
    nrows = pf.metadata.num_rows
    nrgs = pf.num_row_groups

    print(f'=== {args.path} ===')
    print(f'rows: {nrows}    row_groups: {nrgs}')
    if pf.metadata.metadata:
        meta = pf.metadata.metadata
        print('parquet footer metadata:')
        for k in sorted(meta.keys()):
            kk = k.decode('utf-8', 'replace')
            vv = meta[k].decode('utf-8', 'replace')
            print(f'  {kk} = {vv}')

    if not args.cwt_only:
        schema = pf.schema_arrow
        print(f'columns ({len(schema)}):')
        for f in schema:
            print(f'  {f.name:<32} {f.type}')

    table = pq.read_table(args.path, columns=['cwt_candidates'])
    col = table.column('cwt_candidates')
    nonempty = 0
    total_cands = 0
    malformed = 0
    counts = []
    for chunk in col.chunks:
        for v in chunk:
            blob = v.as_py()
            n = parse_cwt_blob(blob) if isinstance(blob, (bytes, bytearray)) else 0
            if n < 0:
                malformed += 1
            elif n > 0:
                nonempty += 1
                total_cands += n
                counts.append(n)
    frac = (nonempty / nrows) if nrows else 0.0
    print(f'cwt_candidates:')
    print(f'  rows with >=1 candidate: {nonempty}/{nrows} ({frac*100:.2f}%)')
    print(f'  total candidates:        {total_cands}')
    if malformed:
        print(f'  MALFORMED rows:          {malformed}  (codec mismatch?)')
    if counts:
        counts.sort()
        print(f'  per-row count: min={counts[0]} median={counts[len(counts)//2]} '
              f'max={counts[-1]} (top values: {counts[-3:][::-1]})')

    if args.sample > 0:
        sample = pq.read_table(args.path).slice(0, args.sample).to_pylist()
        print(f'first {args.sample} rows:')
        for i, r in enumerate(sample):
            short = {k: (v if not isinstance(v, (bytes, bytearray))
                         else f'<bytes len={len(v)}>') for k, v in r.items()}
            print(f'  [{i}] {short}')

    if args.exit_on_empty_cwt and frac < 0.5:
        print(f'EXIT-NONZERO: cwt fraction {frac*100:.1f}% < 50%')
        sys.exit(1)
    sys.exit(0)


def run_diff(args):
    """Compare two parquets, aligning by entry_id."""
    import pyarrow as pa
    import pyarrow.compute as pc
    a_path = args.path
    b_path = args.diff
    print(f'=== A: {a_path}')
    print(f'=== B: {b_path}')
    a = pq.read_table(a_path)
    b = pq.read_table(b_path)
    print(f'A rows: {a.num_rows}    B rows: {b.num_rows}')
    if a.column_names != b.column_names:
        only_a = sorted(set(a.column_names) - set(b.column_names))
        only_b = sorted(set(b.column_names) - set(a.column_names))
        if only_a:
            print(f'columns only in A: {only_a}')
        if only_b:
            print(f'columns only in B: {only_b}')

    if 'entry_id' not in a.column_names or 'entry_id' not in b.column_names:
        print('ERROR: entry_id missing in one or both parquets; cannot align')
        sys.exit(2)

    a_ids = set(a.column('entry_id').to_pylist())
    b_ids = set(b.column('entry_id').to_pylist())
    common = a_ids & b_ids
    only_a = a_ids - b_ids
    only_b = b_ids - a_ids
    print(f'entry_id row sets:')
    print(f'  common:   {len(common)}')
    print(f'  only A:   {len(only_a)}'
          + (f'  (sample: {sorted(list(only_a))[:5]})' if only_a else ''))
    print(f'  only B:   {len(only_b)}'
          + (f'  (sample: {sorted(list(only_b))[:5]})' if only_b else ''))

    # Sort both by entry_id and filter to common ids for column compare
    a_filt = a.filter(pc.is_in(a.column('entry_id'),
                               value_set=pa.array(sorted(common), type=pa.uint32()))).sort_by('entry_id')
    b_filt = b.filter(pc.is_in(b.column('entry_id'),
                               value_set=pa.array(sorted(common), type=pa.uint32()))).sort_by('entry_id')
    if a_filt.num_rows != b_filt.num_rows:
        print(f'ERROR after filter: {a_filt.num_rows} vs {b_filt.num_rows} rows; '
              'duplicate entry_ids?')
        sys.exit(2)

    print(f'per-column diff (numeric tol={args.tolerance:g}):')
    cols = [n for n in a.column_names if n in b.column_names]
    n_diff_cols = 0
    for col in cols:
        ca = a_filt.column(col)
        cb = b_filt.column(col)
        if ca.type != cb.type:
            print(f'  [TYPE] {col:<32} A={ca.type} B={cb.type}')
            n_diff_cols += 1
            continue
        is_numeric = pa.types.is_integer(ca.type) or pa.types.is_floating(ca.type)
        if is_numeric:
            casted_a = pc.cast(ca, pa.float64())
            casted_b = pc.cast(cb, pa.float64())
            absdiff = pc.abs(pc.subtract(casted_a, casted_b))
            within = pc.less_equal(absdiff, args.tolerance).fill_null(False)
            both_null = pc.and_(ca.is_null(), cb.is_null())
            ok = pc.or_(within, both_null)
            n_diff = a_filt.num_rows - (pc.sum(pc.cast(ok, 'int64')).as_py() or 0)
            try:
                max_d = pc.max(absdiff).as_py() or 0.0
            except Exception:
                max_d = float('nan')
            if n_diff == 0:
                print(f'  [OK ] {col:<32} max_abs_diff={max_d:.4e}')
            else:
                n_diff_cols += 1
                print(f'  [DIFF] {col:<32} n_diff={n_diff}/{a_filt.num_rows} '
                      f'max_abs_diff={max_d:.4e}')
        else:
            # Binary blobs / strings: byte equality
            eq = pc.equal(ca, cb)
            both_null = pc.and_(ca.is_null(), cb.is_null())
            ok = pc.or_(eq.fill_null(False), both_null)
            n_diff = a_filt.num_rows - (pc.sum(pc.cast(ok, 'int64')).as_py() or 0)
            if n_diff == 0:
                print(f'  [OK ] {col:<32} (binary/string equality)')
            else:
                n_diff_cols += 1
                print(f'  [DIFF] {col:<32} n_diff={n_diff}/{a_filt.num_rows} (binary/string)')

    print(f'summary: {n_diff_cols} divergent column(s); '
          f'{len(only_a)} only-A and {len(only_b)} only-B entries')
    sys.exit(0 if (n_diff_cols == 0 and not only_a and not only_b) else 1)


def pa_array_int(s):
    import pyarrow as pa
    return pa.array(sorted(s), type=pa.uint32())


if __name__ == '__main__':
    main()
