#!/usr/bin/env python3
"""Compare two directories of Osprey .scores.parquet files for DATA equality.

The question this answers is the one ParquetScoreCache's version guard cannot: not
"was this scored by exactly my binary?" but "is this scoring identical to mine?".
`osprey.version` is excluded from the metadata comparison by design - it is the field
under test.  Every other metadata key, the schema, the row count and every value are
compared exactly, bitwise, so a 1-ULP float drift is a difference and not a rounding
success.

Usage:
    Compare-ScoreParquets.py <dirA> <dirB> [--limit N] [--quiet]

Exit code 0 = every common file is data-identical, 1 = at least one differs,
2 = the two directories do not hold the same file set.
"""
import argparse
import hashlib
import os
import sys
from glob import glob

import pyarrow.parquet as pq

IGNORED_META = {b"osprey.version"}


def col_digest(col):
    """Bitwise digest of one column's values, chunking-independent."""
    arr = col.combine_chunks() if hasattr(col, "combine_chunks") else col
    if hasattr(arr, "chunks"):                    # a 1-chunk ChunkedArray
        arr = arr.chunks[0] if arr.chunks else arr
    h = hashlib.blake2b(digest_size=16)
    for buf in arr.buffers():
        h.update(b"\x00" if buf is None else memoryview(buf).tobytes())
    return h.hexdigest()


def value_diff(ta, tb, name, max_report=5):
    """Row-level detail once a column is known to differ, so a report can say WHICH."""
    a, b = ta.column(name).to_pylist(), tb.column(name).to_pylist()
    bad = [i for i, (x, y) in enumerate(zip(a, b))
           if not (x == y or (x != x and y != y))]     # NaN == NaN for this purpose
    out = [f"        {len(bad)} of {len(a)} rows differ"]
    for i in bad[:max_report]:
        out.append(f"          row {i}: {a[i]!r} vs {b[i]!r}")
    return bad, out


def compare_one(pa_path, pb_path):
    """Return (ok, list_of_lines)."""
    fa, fb = pq.ParquetFile(pa_path), pq.ParquetFile(pb_path)
    lines, ok = [], True

    ma = {k: v for k, v in (fa.schema_arrow.metadata or {}).items() if k not in IGNORED_META}
    mb = {k: v for k, v in (fb.schema_arrow.metadata or {}).items() if k not in IGNORED_META}
    if ma != mb:
        ok = False
        for k in sorted(set(ma) | set(mb)):
            if ma.get(k) != mb.get(k):
                lines.append(f"        metadata {k.decode()}: "
                             f"{ma.get(k, b'<absent>')!r} vs {mb.get(k, b'<absent>')!r}")

    if fa.schema_arrow.names != fb.schema_arrow.names:
        return False, lines + [f"        column set differs: "
                               f"{fa.schema_arrow.names} vs {fb.schema_arrow.names}"]
    if fa.metadata.num_rows != fb.metadata.num_rows:
        return False, lines + [f"        row count {fa.metadata.num_rows} vs "
                               f"{fb.metadata.num_rows}"]

    ta, tb = fa.read(), fb.read()
    for name in ta.schema.names:
        if ta.schema.field(name).type != tb.schema.field(name).type:
            ok = False
            lines.append(f"        column {name}: type "
                         f"{ta.schema.field(name).type} vs {tb.schema.field(name).type}")
            continue
        if col_digest(ta.column(name)) != col_digest(tb.column(name)):
            bad, detail = value_diff(ta, tb, name)
            if bad:                       # a buffer-only difference with equal values
                ok = False                # (padding, null-buffer shape) is not a data diff
                lines.append(f"        column {name}: DIFFERS")
                lines.extend(detail)
    return ok, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a")
    ap.add_argument("dir_b")
    ap.add_argument("--limit", type=int, default=0, help="compare at most N files")
    ap.add_argument("--quiet", action="store_true", help="only print files that differ")
    args = ap.parse_args()

    def stems(d):
        return {os.path.basename(p): p for p in glob(os.path.join(d, "*.scores.parquet"))}

    sa, sb = stems(args.dir_a), stems(args.dir_b)
    common = sorted(set(sa) & set(sb))
    only_a, only_b = sorted(set(sa) - set(sb)), sorted(set(sb) - set(sa))
    print(f"A: {args.dir_a}  ({len(sa)} parquet)")
    print(f"B: {args.dir_b}  ({len(sb)} parquet)")
    print(f"common: {len(common)}   only-A: {len(only_a)}   only-B: {len(only_b)}")
    for n in only_a[:5]:
        print(f"    only in A: {n}")
    for n in only_b[:5]:
        print(f"    only in B: {n}")
    if not common:
        return 2

    if args.limit:
        common = common[: args.limit]
    n_same = 0
    differing = []
    for name in common:
        ok, lines = compare_one(sa[name], sb[name])
        if ok:
            n_same += 1
            if not args.quiet:
                print(f"    SAME  {name}")
        else:
            differing.append(name)
            print(f"    DIFF  {name}")
            for ln in lines:
                print(ln)

    print(f"\n{n_same} of {len(common)} compared file(s) are data-identical "
          f"(osprey.version excluded).")
    if differing:
        print(f"{len(differing)} differ: {', '.join(differing[:10])}"
              f"{' ...' if len(differing) > 10 else ''}")
        return 1
    return 0 if not (only_a or only_b) else 2


if __name__ == "__main__":
    sys.exit(main())
