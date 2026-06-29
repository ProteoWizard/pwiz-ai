"""Tolerance-based diff for Osprey .fdr_scores.bin sidecars.

Value-level comparator (companion to json_tol_diff.py / parquet_diff.py). The
.fdr_scores.bin files are bit-different cross-impl only at f64 ULP scale (bit-
exact given identical input), so a raw SHA over-reports. This decodes both and
compares values by entry_id.

Binary format (little-endian; mirror of FdrScoresSidecar.cs):
    header (32 bytes): 8s magic, B version, B pass, 6x reserved,
                       Q entry_count, 8x reserved
    record (60 bytes): I entry_id, 7d
                       [Score, RunPrecursorQvalue, RunPeptideQvalue,
                        ExperimentPrecursorQvalue, ExperimentPeptideQvalue,
                        Pep, RunProteinQvalue]

Exit 0 if the entry-id sets match and every numeric field is within
--tolerance for every common entry; 1 otherwise.

Usage: python bin_tol_diff.py <a.bin> <b.bin> [--tolerance 1e-9]
"""
import argparse
import struct
import sys

FIELDS = ["Score", "RunPrecursorQvalue", "RunPeptideQvalue",
          "ExperimentPrecursorQvalue", "ExperimentPeptideQvalue",
          "Pep", "RunProteinQvalue"]
HEADER = struct.Struct("<8sBB6sQ8s")  # 32 bytes
RECORD = struct.Struct("<I7d")        # 60 bytes


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    _magic, ver, pas, _r1, count, _r2 = HEADER.unpack_from(data, 0)
    out = {}
    off = HEADER.size
    for _ in range(count):
        vals = RECORD.unpack_from(data, off)
        out[vals[0]] = vals[1:]
        off += RECORD.size
    return ver, pas, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--tolerance", type=float, default=1e-9)
    args = ap.parse_args()

    va, pa, a = load(args.a)
    vb, pb, b = load(args.b)
    ka, kb = set(a), set(b)
    only_a, only_b = ka - kb, kb - ka
    common = ka & kb
    ok = True

    print("=== %s: %d records (v%d pass%d) ===" % (args.a, len(a), va, pa))
    print("=== %s: %d records (v%d pass%d) ===" % (args.b, len(b), vb, pb))
    print("=== tolerance: %g ===" % args.tolerance)
    if only_a or only_b:
        ok = False
        print("ENTRY-ID SET DIFFERS: only_a=%d only_b=%d" % (len(only_a), len(only_b)))

    max_diff = [0.0] * len(FIELDS)
    n_diverg = [0] * len(FIELDS)
    for k in common:
        av, bv = a[k], b[k]
        for i in range(len(FIELDS)):
            d = abs(av[i] - bv[i])
            if d > max_diff[i]:
                max_diff[i] = d
            if d > args.tolerance:
                n_diverg[i] += 1
    for i, name in enumerate(FIELDS):
        status = "PASS" if n_diverg[i] == 0 else "FAIL"
        if n_diverg[i] != 0:
            ok = False
        print("  %-28s %s  max_diff=%.3e  n_diverg=%d/%d"
              % (name, status, max_diff[i], n_diverg[i], len(common)))

    print("OVERALL: " + ("PASS" if ok else "FAIL"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
