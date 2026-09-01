#!/usr/bin/env python3
"""Change the Osprey build stamp on per-file artifacts WITHOUT re-scoring them.

`ParquetScoreCache.CheckParquetMetadata` hard-fails on any `osprey.version`
difference, including a different daily build of the same release line, so a
cohort scored across two days cannot be joined even when the scoring is
provably identical.  Re-scoring a plate to fix a ten-character string costs
hours; this costs milliseconds.

The stamp lives in more places than the parquet, and every one that a run will
read has to move together or it fails on whichever was left behind:

    <stem>.scores.parquet                                  footer key-value metadata
    <stem>.scores.parquet.PerFileScoring.osprey.task       JSON "version"
    <stem>.calibration.json.PerFileScoring.osprey.task     JSON "version"

so this patches the parquet plus EVERY `<stem>.*.PerFileScoring.osprey.task`.
`.calibration.json` itself carries no version and is left alone, and neither are
the later stages' task files or their binary sidecars - those embed the version
internally, so restamping the marker without the sidecar would create exactly
the inconsistency this tool exists to avoid.

That leaves `OspreyDatasetRun.psm1`'s auto-pin, which globs `*.osprey.task` and
reads whichever sorts first - for a plate directory that is
`.1st-pass.fdr_scores.bin.FirstPassFDR.osprey.task`, which this deliberately does
NOT touch.  **Pass `OSPREY_VERSION_OVERRIDE` explicitly on the consuming run** so
the auto-pin is skipped rather than reading a stamp from a stage that is about to
be recomputed anyway.

The parquet edit is an in-place same-length byte patch of the footer metadata.
Parquet's page CRCs cover data pages only, never the footer, and a same-length
value changes no offset or length anywhere, so no row group is touched or
rewritten.  The patch site is located structurally - inside the footer window
named by the trailing 4-byte length, immediately after the `osprey.version`
key - never by searching the whole file for a version-shaped string.

USE THIS ONLY WITH EVIDENCE.  The guard asks "was this scored by exactly my
binary?"; restamping asserts the different and stronger claim "this scoring is
identical to my binary's".  Establish that first by re-scoring a sample of the
same files on the new build and diffing with Compare-ScoreParquets.py.  Without
that, this tool converts a loud refusal into a silently mixed-scoring run,
which is the exact failure the guard's own comment describes.

OSPREY_VERSION_OVERRIDE is the alternative and needs no file edits, but it pins
what the new run WRITES as well as what it accepts, so a 446-file join would
stamp itself with the old build's version.  Restamping the inputs keeps the
join's own provenance honest; that is the only reason to prefer it.

Every change is recorded in `osprey-version-restamp.json` beside the artifacts
and is exactly reversible by running the tool again in the other direction.

Usage:
    Restamp-OspreyVersion.py <dir> [<dir> ...] --to 26.1.1.243 [--from 26.1.1.233]
                                    [--dry-run] [--quiet]
"""
import argparse
import datetime
import json
import os
import re
import sys
from glob import glob

import pyarrow.parquet as pq

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+\.\d+$")
KEY = b"osprey.version"
# Every PerFileScoring completion marker for a stem, not just the parquet's. Missing the
# calibration one let a run pin the wrong version from it and refuse the parquet in 1 second.
TASK_GLOB = "*.PerFileScoring.osprey.task"


class PatchError(Exception):
    pass


def read_parquet_version(path):
    md = pq.ParquetFile(path).schema_arrow.metadata or {}
    v = md.get(KEY)
    return v.decode() if v else None


def footer_window(fh, size):
    """Byte range [start, end) of the thrift file-metadata blob."""
    fh.seek(size - 8)
    tail = fh.read(8)
    if tail[4:] != b"PAR1":
        raise PatchError("not a parquet file (no trailing PAR1 magic)")
    footer_len = int.from_bytes(tail[:4], "little")
    start = size - 8 - footer_len
    if start < 4:
        raise PatchError("implausible footer length %d" % footer_len)
    return start, size - 8


def locate_version_offset(path, current):
    """Absolute file offset of the version VALUE bytes, located structurally."""
    cur = current.encode()
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        start, end = footer_window(fh, size)
        fh.seek(start)
        footer = fh.read(end - start)

    hits = [m.start() for m in re.finditer(re.escape(KEY), footer)]
    if len(hits) != 1:
        raise PatchError("expected exactly 1 '%s' key in the footer, found %d"
                         % (KEY.decode(), len(hits)))
    key_end = hits[0] + len(KEY)

    # Thrift writes the KeyValue value right after the key: a field header and a
    # varint length, a handful of bytes.  Searching a small window rather than the
    # whole footer is what keeps this from matching a version-shaped string that
    # happens to live in column statistics.
    window = footer[key_end:key_end + 16]
    vhits = [m.start() for m in re.finditer(re.escape(cur), window)]
    if len(vhits) != 1:
        raise PatchError("expected exactly 1 occurrence of %r within 16 bytes after the key, "
                         "found %d" % (current, len(vhits)))
    return start + key_end + vhits[0], size


def patch_parquet(path, current, new, dry_run):
    if len(new) != len(current):
        raise PatchError(
            "version lengths differ (%r -> %r); the in-place patch needs equal lengths. "
            "A streamed rewrite would be required, which re-encodes row groups."
            % (current, new))
    off, size_before = locate_version_offset(path, current)
    if dry_run:
        return off, size_before

    with open(path, "r+b") as fh:
        fh.seek(off)
        fh.write(new.encode())
        fh.flush()
        os.fsync(fh.fileno())

    # Read back through a real parquet reader.  Confirming the bytes changed proves
    # nothing about whether the footer still parses.
    f = pq.ParquetFile(path)
    got = (f.schema_arrow.metadata or {}).get(KEY, b"").decode()
    if got != new:
        raise PatchError("read-back says %r, expected %r" % (got, new))
    if os.path.getsize(path) != size_before:
        raise PatchError("file size changed; the patch was not in place")
    # Decode one column of one row group, so a corrupted footer that still parses
    # but no longer addresses its data is caught here rather than hours into a run.
    if f.metadata.num_row_groups:
        f.read_row_group(0, columns=[f.schema_arrow.names[0]])
    return off, size_before


def patch_task(path, current, new, dry_run):
    """Replace the version substring in place, NOT by re-serializing the document.

    A json.load/json.dump round trip reformats whitespace and line endings, so the
    file stops being byte-identical to what Osprey wrote and the edit can no longer
    be proven to have changed only the stamp.  Rewriting the one quoted value keeps
    the round trip exact in both directions.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    doc = json.loads(raw.decode("utf-8"))
    if doc.get("version") != current:
        raise PatchError("task version is %r, expected %r" % (doc.get("version"), current))
    if dry_run:
        return
    validity = doc.get("validity_key")

    needle = ('"version": "%s"' % current).encode()
    hits = raw.count(needle)
    if hits != 1:
        raise PatchError("expected exactly 1 %r in the task file, found %d"
                         % (needle.decode(), hits))
    patched = raw.replace(needle, ('"version": "%s"' % new).encode())
    if len(patched) != len(raw):
        raise PatchError("task rewrite changed the file length")

    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(patched)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)

    with open(path, "r", encoding="utf-8") as fh:
        back = json.load(fh)
    if back.get("version") != new:
        raise PatchError("task read-back says %r, expected %r" % (back.get("version"), new))
    if back.get("validity_key") != validity:
        raise PatchError("task validity_key changed during rewrite")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--to", required=True, help="target version, e.g. 26.1.1.243")
    ap.add_argument("--from", dest="from_", default=None,
                    help="only restamp files currently at this version (a safety filter)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if not VERSION_RE.match(args.to):
        print("--to %r is not a YEAR.ORDINAL.BRANCH.DOY version" % args.to, file=sys.stderr)
        return 2

    total_ok = total_skip = total_fail = 0
    for d in args.dirs:
        parquets = sorted(glob(os.path.join(d, "*.scores.parquet")))
        print("\n=== %s  (%d parquet) ===" % (d, len(parquets)))
        record = []
        for p in parquets:
            stem = os.path.basename(p)[: -len(".scores.parquet")]
            tasks = sorted(glob(os.path.join(d, stem + TASK_GLOB)))
            try:
                cur = read_parquet_version(p)
                if cur is None:
                    raise PatchError("parquet has no osprey.version metadata")
                if cur == args.to:
                    total_skip += 1
                    if not args.quiet:
                        print("    skip  %s  already %s" % (stem, cur))
                    continue
                if args.from_ and cur != args.from_:
                    total_skip += 1
                    print("    SKIP  %s  is %s, --from says %s" % (stem, cur, args.from_))
                    continue
                if not tasks:
                    raise PatchError("no %s beside the parquet" % TASK_GLOB)
                # Check every task file BEFORE writing anything, so a stem is never left with
                # a patched parquet and an unpatched marker.
                for t in tasks:
                    with open(t, encoding="utf-8") as fh:
                        tv = json.load(fh).get("version")
                    if tv != cur:
                        raise PatchError("%s reads %r but the parquet reads %r"
                                         % (os.path.basename(t), tv, cur))
                off, _ = patch_parquet(p, cur, args.to, args.dry_run)
                for t in tasks:
                    patch_task(t, cur, args.to, args.dry_run)
                total_ok += 1
                record.append({"stem": stem, "from": cur, "to": args.to, "parquet_offset": off,
                               "tasks": [os.path.basename(t) for t in tasks]})
                if not args.quiet:
                    print("    %srestamp  %s  %s -> %s  (+%d task file(s))"
                          % ("would " if args.dry_run else "", stem, cur, args.to, len(tasks)))
            except Exception as exc:                       # noqa: BLE001 - reported per file
                total_fail += 1
                print("    FAIL  %s: %s" % (stem, exc))

        if record and not args.dry_run:
            side = os.path.join(d, "osprey-version-restamp.json")
            prev = []
            if os.path.exists(side):
                with open(side, encoding="utf-8") as fh:
                    prev = json.load(fh)
            prev.append({
                "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "tool": os.path.basename(__file__),
                "to": args.to,
                "files": record,
            })
            with open(side, "w", encoding="utf-8") as fh:
                json.dump(prev, fh, indent=2)
            print("    provenance -> %s" % side)

    verb = "would restamp" if args.dry_run else "restamped"
    print("\n%s %d, skipped %d, failed %d" % (verb, total_ok, total_skip, total_fail))
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main())
