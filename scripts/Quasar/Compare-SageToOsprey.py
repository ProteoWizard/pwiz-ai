"""Compare a Sage search of Quasar pseudo-spectra with Osprey's identifications of the same run.

The positive control of the Quasar spec (Phase 1): Quasar's clusters, searched by Rust Sage,
should re-find the peptides Osprey found, at the same retention times. Osprey's truth is its
blib: precursors whose q-value in this run is at or below the threshold, with their apex times,
from RetentionTimes (one row per precursor and run; OspreyRunScores and OspreyPeakBoundaries
hold only each precursor's best run, a third of a run's detections on the Astral set). Only
Osprey precursors whose m/z falls in an isolation window Quasar processed count.

Standard library only (run with `python -I`):

    python -I Compare-SageToOsprey.py --sage <results.sage.tsv> [<more.sage.tsv> ...] --blib <osprey.blib>
        --quasar-mzml <run.quasar.mzML> [--q 0.01] [--out <prefix>]

Several --sage files (for example the narrow-tolerance search of the precursor-candidate mzML and
the wide-window search of every cluster) are each cut at --q on their own q-values and reported as
a union; the union's FDR can be up to the sum of the separate ones.

Writes <prefix>.matched.tsv (peptides both found, with both apex times) and
<prefix>.sage-only.tsv when --out is given.
"""
import argparse
import csv
import re
import sqlite3
import statistics
import sys
from pathlib import Path

MOD_PATTERN = re.compile(r"\[[^\]]*\]|\([^)]*\)")


def strip_mods(sequence):
    """Plain amino-acid sequence: modifications in [] or () and terminal markers removed."""
    return MOD_PATTERN.sub("", sequence).replace("-", "").replace(".", "")


def read_windows(mzml_path):
    """Isolation windows (low, high) and the run stem from a Quasar mzML."""
    text = Path(mzml_path).read_text(encoding="utf-8", errors="replace")
    windows = set()
    pattern = re.compile(
        r'accession="MS:1000827"[^>]*value="([^"]+)"[\s\S]*?accession="MS:1000828"[^>]*value="([^"]+)"'
        r'[\s\S]*?accession="MS:1000829"[^>]*value="([^"]+)"')
    for target, lower, upper in pattern.findall(text):
        t = float(target)
        windows.add((round(t - float(lower), 4), round(t + float(upper), 4)))
    stem_match = re.search(r'id="run=([^ "]+) window=', text)
    return sorted(windows), (stem_match.group(1) if stem_match else None)


def read_boundaries(mzml_path):
    """Quasar's boundaries per spectrum id: (start_rt, end_rt) userParams, in minutes."""
    text = Path(mzml_path).read_text(encoding="utf-8", errors="replace")
    pattern = re.compile(r'<spectrum [^>]*id="([^"]+)"[^>]*>[\s\S]*?name="start_rt" value="([^"]+)"'
                         r'[\s\S]*?name="end_rt" value="([^"]+)"')
    return {m.group(1): (float(m.group(2)), float(m.group(3))) for m in pattern.finditer(text)}


def read_sage(path, q, levels):
    """Target PSMs at or below q (spectrum and peptide level), and the decoy count at the same cut."""
    targets, decoys = [], 0
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if any(float(row[level]) > q for level in levels):
                continue
            if row["label"] == "1":
                targets.append(row)
            else:
                decoys += 1
    return targets, decoys


def read_osprey(blib_path, stem, windows, q):
    """Osprey precursors passing q in this run, inside the processed windows: sequence -> apex RT."""
    db = sqlite3.connect(f"file:{blib_path}?mode=ro", uri=True)
    rows = db.execute(
        """select r.peptideSeq, r.precursorMZ, r.precursorCharge, t.score, t.retentionTime,
                  t.startTime, t.endTime
           from RetentionTimes t
           join SpectrumSourceFiles f on f.id = t.SpectrumSourceID
           join RefSpectra r on r.id = t.RefSpectraID
           where f.fileName like ? and t.score <= ?""",
        (f"%{stem}%", q)).fetchall()
    truth = {}
    for sequence, mz, charge, _, apex, start, end in rows:
        if any(low <= mz < high for low, high in windows):
            truth.setdefault(sequence, []).append((mz, charge, apex, start, end))
    return truth


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sage", required=True, nargs="+")
    parser.add_argument("--blib", required=True)
    parser.add_argument("--quasar-mzml", required=True)
    parser.add_argument("--q", type=float, default=0.01)
    parser.add_argument("--out")
    parser.add_argument("--stem", help="run name to look up in the blib (default: from the mzML spectrum ids)")
    parser.add_argument("--q-levels", default="spectrum_q,peptide_q",
                        help="Sage q-value columns that must all pass (comma-separated)")
    args = parser.parse_args()

    windows, stem = read_windows(args.quasar_mzml)
    if not windows or not (stem or args.stem):
        sys.exit("no isolation windows or run id found in " + args.quasar_mzml)
    stem = args.stem or stem
    targets, decoys = [], 0
    for path in args.sage:
        file_targets, file_decoys = read_sage(path, args.q, args.q_levels.split(","))
        if len(args.sage) > 1:
            peptides = len({strip_mods(row["peptide"]) for row in file_targets})
            print(f"{path}: {len(file_targets)} target PSMs, {file_decoys} decoy PSMs, {peptides} peptides")
        targets += file_targets
        decoys += file_decoys
    truth = read_osprey(args.blib, stem, windows, args.q)

    sage_best = {}
    for row in targets:
        sequence = strip_mods(row["peptide"])
        if sequence not in sage_best or float(row["hyperscore"]) > float(sage_best[sequence]["hyperscore"]):
            sage_best[sequence] = row
    matched = sorted(set(sage_best) & set(truth))
    sage_only = sorted(set(sage_best) - set(truth))
    boundaries = read_boundaries(args.quasar_mzml)
    rt_diffs, start_diffs, end_diffs = [], [], []
    for sequence in matched:
        sage_rt = float(sage_best[sequence]["rt"])
        nearest = min(truth[sequence], key=lambda t: abs(t[2] - sage_rt))
        rt_diffs.append(abs(sage_rt - nearest[2]) * 60.0)
        bounds = boundaries.get(sage_best[sequence]["scannr"])
        if bounds:
            start_diffs.append((bounds[0] - nearest[3]) * 60.0)
            end_diffs.append((bounds[1] - nearest[4]) * 60.0)

    print(f"run {stem}: {len(windows)} windows, m/z {windows[0][0]:.2f}-{windows[-1][1]:.2f}")
    print(f"Sage at q <= {args.q}: {len(targets)} target PSMs, {decoys} decoy PSMs, {len(sage_best)} peptides")
    print(f"Osprey at q <= {args.q} in these windows: {len(truth)} peptides")
    recall = len(matched) / len(truth) if truth else float("nan")
    print(f"Found by both: {len(matched)} ({recall:.1%} of Osprey's); Sage only: {len(sage_only)}")
    if rt_diffs:
        print(f"Apex time difference, both found: median {statistics.median(rt_diffs):.1f} s, "
              f"90th percentile {sorted(rt_diffs)[int(0.9 * (len(rt_diffs) - 1))]:.1f} s")
    if start_diffs:
        def spread(values):
            q = statistics.quantiles(values, n=4)
            return f"median {statistics.median(values):+.1f} s (quartiles {q[0]:+.1f}, {q[2]:+.1f})"
        print(f"Boundaries, Quasar minus Osprey: start {spread(start_diffs)}; end {spread(end_diffs)}; "
              f"width difference median {statistics.median((e - s) for s, e in zip(start_diffs, end_diffs)):+.1f} s")

    if args.out:
        with open(args.out + ".matched.tsv", "w", encoding="utf-8") as handle:
            handle.write("sequence\tsage_rt\tosprey_apex_rt\thyperscore\tscannr\n")
            for sequence in matched:
                row = sage_best[sequence]
                osprey_rt = min((t[2] for t in truth[sequence]), key=lambda a: abs(a - float(row["rt"])))
                handle.write(f"{sequence}\t{row['rt']}\t{osprey_rt}\t{row['hyperscore']}\t{row['scannr']}\n")
        with open(args.out + ".sage-only.tsv", "w", encoding="utf-8") as handle:
            handle.write("sequence\tpeptide\trt\thyperscore\tscannr\n")
            for sequence in sage_only:
                row = sage_best[sequence]
                handle.write(f"{sequence}\t{row['peptide']}\t{row['rt']}\t{row['hyperscore']}\t{row['scannr']}\n")


if __name__ == "__main__":
    main()
