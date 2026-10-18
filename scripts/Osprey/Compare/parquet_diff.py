"""Content-level diff between two reconciled .scores.parquet files.

Promoted from ai/.tmp during the Stage 6 Osprey port. Used during
the original Rust port to bisect bit-parity regressions between
Stage 1-4 pipeline-fed runs and Stage 5 sidecar-fed runs; reused now
to validate cross-impl byte parity of end-of-Stage-6 reconciled
.scores.parquet output between Rust osprey and Osprey.

Compares two parquet files row-by-row after sorting on entry_id.
Prints one line per column: [OK ] / [DIFF] with the row count that
differs (above tolerance), sample mismatches, and max abs diff.

Numeric columns: rows where |a-b| <= tolerance are treated as matching.
Default tolerance is 1e-6, mirroring Test-Features.ps1's gate. Pass
--tolerance 0 to require bit-exact byte parity.

Exit code: 0 if every column matches (within tolerance), 1 otherwise.

--common-entries reports the entry_id set difference (with samples) and then compares every
column over the entry_ids both files hold, instead of stopping at a row-count mismatch. Use it
where the two sides' candidate sets legitimately differ by a few rows - the Stage 4
.scores.parquet of Rust vs C# (DIAGNOSTICS.md, main-search feature parity). The exit code is
still 1 when the sets differ.

Usage:
    python parquet_diff.py <a.parquet> <b.parquet> [--tolerance N] [--common-entries]
"""
import argparse
import sys
import pyarrow as pa
import pyarrow.parquet as pq
import pyarrow.compute as pc


def _is_numeric(t):
    return pa.types.is_integer(t) or pa.types.is_floating(t)


def load_sorted(path):
    t = pq.read_table(path)
    return t.sort_by("entry_id")


def diff_tables(a, b, label_a="A", label_b="B", tolerance=0.0):
    print(f"=== {label_a}: {a.num_rows} rows / {len(a.column_names)} cols ===")
    print(f"=== {label_b}: {b.num_rows} rows / {len(b.column_names)} cols ===")
    if tolerance > 0:
        print(f"=== numeric tolerance: {tolerance:g} ===")

    if a.num_rows != b.num_rows:
        print(f"ROW COUNT DIFFERS: {a.num_rows} vs {b.num_rows}")
        return False
    if a.column_names != b.column_names:
        print(f"COLUMNS DIFFER: {a.column_names} vs {b.column_names}")
        return False

    all_match = True
    for col_name in a.column_names:
        ca = a.column(col_name)
        cb = b.column(col_name)
        is_numeric = _is_numeric(ca.type)

        if is_numeric and tolerance > 0:
            # Numeric tolerance: |a-b| <= tolerance counts as match.
            # Both-null also counts as match. NaN/Inf produce non-matches
            # (their abs diff is NaN, which fails the <= tolerance check).
            both_null = pc.and_(ca.is_null(), cb.is_null())
            casted_a = pc.cast(ca, pa.float64())
            casted_b = pc.cast(cb, pa.float64())
            absdiff = pc.abs(pc.subtract(casted_a, casted_b))
            within_tol = pc.less_equal(absdiff, tolerance).fill_null(False)
            eq_or_both_null = pc.or_(within_tol, both_null)
        else:
            eq = pc.equal(ca, cb)
            both_null = pc.and_(ca.is_null(), cb.is_null())
            eq_or_both_null = pc.or_(eq.fill_null(False), both_null)

        n_match = pc.sum(pc.cast(eq_or_both_null, "int64")).as_py() or 0
        n_diff = a.num_rows - n_match
        marker = "OK " if n_diff == 0 else "DIFF"
        print(f"  [{marker}] {col_name}: {n_diff} rows differ")
        if n_diff > 0:
            all_match = False
            try:
                diff_mask = pc.invert(eq_or_both_null)
                diff_a = ca.filter(diff_mask)
                diff_b = cb.filter(diff_mask)
                print("        sample mismatches:")
                for i in range(min(3, len(diff_a))):
                    va = diff_a[i].as_py()
                    vb = diff_b[i].as_py()
                    if isinstance(va, (bytes, str)) and len(va) > 80:
                        va = repr(va[:80]) + "..."
                    if isinstance(vb, (bytes, str)) and len(vb) > 80:
                        vb = repr(vb[:80]) + "..."
                    print(f"          [{i}]: A={va!r}  B={vb!r}")
                if is_numeric:
                    try:
                        absdiff = pc.abs(pc.subtract(diff_a, diff_b))
                        max_d = pc.max(absdiff).as_py()
                        print(f"        max abs diff: {max_d}")
                    except Exception:
                        pass
            except Exception as e:
                print(f"        (could not inspect diffs: {e})")
    return all_match


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("a", help="first parquet file")
    p.add_argument("b", help="second parquet file")
    p.add_argument("--tolerance", type=float, default=0.0,
                   help="numeric tolerance: rows where |a-b| <= tolerance match (default 0 = exact)")
    p.add_argument("--common-entries", action="store_true",
                   help="report the entry_id set difference, then compare over the shared entry_ids")
    args = p.parse_args()
    a = load_sorted(args.a)
    b = load_sorted(args.b)
    sets_match = True
    if args.common_entries:
        ids_a = set(a.column("entry_id").to_pylist())
        ids_b = set(b.column("entry_id").to_pylist())
        only_a = sorted(ids_a - ids_b)
        only_b = sorted(ids_b - ids_a)
        common = pa.array(sorted(ids_a & ids_b), type=a.schema.field("entry_id").type)
        print(f"=== entry_ids: {len(common)} common, {len(only_a)} only in A {only_a[:5]}, "
              f"{len(only_b)} only in B {only_b[:5]} ===")
        sets_match = not only_a and not only_b
        a = a.filter(pc.is_in(a.column("entry_id"), value_set=common))
        b = b.filter(pc.is_in(b.column("entry_id"), value_set=common))
    ok = diff_tables(a, b, args.a, args.b, tolerance=args.tolerance)
    sys.exit(0 if ok and sets_match else 1)
