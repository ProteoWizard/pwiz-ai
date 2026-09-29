#!/usr/bin/env python3
"""
Compare Osprey searches of the same runs demultiplexed different ways: detections,
entrapment-estimated FDP, and overlap.

Each search is an Osprey output directory run with --fdrbench <dir>/fdrbench.tsv on an
entrapment library (entrapment accessions carry '_p_target', FDRBench's convention).
Read from each directory:
  output.stats.tsv            per-run and experiment precursor/peptide/protein counts
  fdrbench.tsv                every reported target precursor with its q-value
  fdrbench.tsv.pairing.tsv    the searched library's target/entrapment peptides, which
                              give the entrapment ratio r

Entrapment FDP is FDRBench's combined estimate: FDP = N_e (1 + 1/r) / (N_t + N_e), where
N_t and N_e are the accepted non-entrapment and entrapment precursors (or peptides) at the
q-value threshold. Any accepted entrapment identification is known to be false. A shuffled
(_p_target) entrapment shares its target's fragment masses and tends to overstate FDP, but it
does so equally for every search compared here.

Example:
    python Compare-DemuxSearches.py \
        --search msconvert=D:/test/osprey-runs/eclipse-staggered/search-msconvert \
        --search osprey=D:/test/osprey-runs/eclipse-staggered/search-osprey-default
"""

import argparse
import csv
import os
import re
import sys

ENTRAPMENT = "_p_target"

# Monoisotopic residue masses, water and proton, for recomputing precursor m/z so a comparison
# can be restricted to a precursor range every search actually covered.
RESIDUE = {
    "G": 57.021464, "A": 71.037114, "S": 87.032028, "P": 97.052764, "V": 99.068414,
    "T": 101.047679, "C": 103.009185, "L": 113.084064, "I": 113.084064, "N": 114.042927,
    "D": 115.026943, "Q": 128.058578, "K": 128.094963, "E": 129.042593, "M": 131.040485,
    "H": 137.058912, "F": 147.068414, "R": 156.101111, "Y": 163.063329, "W": 186.079313,
    "U": 150.953636, "O": 237.147727,
}
UNIMOD = {"4": 57.021464, "35": 15.994915, "1": 42.010565, "21": 79.966331, "7": 0.984016}
WATER = 18.010565
PROTON = 1.007276


def precursor_mz(mod_peptide, charge):
    mass = WATER
    for residue in re.sub(r"\[[^\]]*\]", "", mod_peptide):
        mass += RESIDUE[residue]
    for unimod in re.findall(r"\[UniMod:(\d+)\]", mod_peptide):
        if unimod not in UNIMOD:
            raise ValueError(f"unknown modification UniMod:{unimod} in {mod_peptide}")
        mass += UNIMOD[unimod]
    z = int(charge)
    return (mass + z * PROTON) / z


def named(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=DIRECTORY")
    return tuple(value.split("=", 1))


def read_stats(directory):
    rows = {}
    with open(os.path.join(directory, "output.stats.tsv"), newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            rows[row["Run"]] = (int(row["Precursors"]), int(row["Peptides"]), int(row["Proteins"]))
    return rows


def entrapment_ratio(directory):
    counts = {"target": 0, "p_target": 0}
    path = os.path.join(directory, "fdrbench.tsv.pairing.tsv")
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            kind = row["peptide_type"]
            if kind in counts:
                counts[kind] += 1
    return counts["p_target"] / counts["target"] if counts["target"] else float("nan")


def read_fdrbench(directory, mz_range):
    """(precursor key -> (q, is_entrapment)), (peptide -> (best q, is_entrapment)), within mz_range."""
    precursors, peptides = {}, {}
    with open(os.path.join(directory, "fdrbench.tsv"), newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if mz_range is not None:
                mz = precursor_mz(row["mod_peptide"], row["charge"])
                if not mz_range[0] <= mz < mz_range[1]:
                    continue
            q = float(row["q_value"])
            entrap = ENTRAPMENT in row["protein"]
            precursors[(row["mod_peptide"], row["charge"])] = (q, entrap)
            best = peptides.get(row["peptide"])
            if best is None or q < best[0]:
                peptides[row["peptide"]] = (q, entrap)
    return precursors, peptides


def accepted(table, threshold):
    targets = {k for k, (q, e) in table.items() if q <= threshold and not e}
    entrapment = {k for k, (q, e) in table.items() if q <= threshold and e}
    return targets, entrapment


def combined_fdp(n_target, n_entrap, ratio):
    total = n_target + n_entrap
    return n_entrap * (1 + 1 / ratio) / total if total else float("nan")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--search", type=named, action="append", required=True,
                        help="NAME=DIRECTORY of an Osprey search (repeatable; the first is the baseline)")
    parser.add_argument("--q", type=float, action="append",
                        help="q-value threshold(s) (default 0.01)")
    parser.add_argument("--precursor-mz", type=float, nargs=2, metavar=("LOW", "HIGH"),
                        help="count only precursors with LOW <= m/z < HIGH (computed from sequence), "
                             "e.g. the range every compared search actually scored")
    args = parser.parse_args()
    thresholds = args.q or [0.01]
    mz_range = tuple(args.precursor_mz) if args.precursor_mz else None
    if mz_range:
        print(f"Restricted to precursor m/z [{mz_range[0]:g}, {mz_range[1]:g}) for the q-value tables "
              f"(output.stats.tsv is unrestricted)\n")

    searches = []
    for name, directory in args.search:
        try:
            searches.append((name, read_stats(directory), entrapment_ratio(directory),
                             *read_fdrbench(directory, mz_range)))
        except OSError as ex:
            print(f"ERROR: {name}: {ex}", file=sys.stderr)
            return 2

    print("Osprey output.stats.tsv (precursors / peptides / proteins at the search's FDR settings)")
    runs = sorted({run for _, stats, *_ in searches for run in stats}, key=lambda r: (r == "Experiment", r))
    print(f"  {'search':22s}" + "".join(f"{run[:34]:>36s}" for run in runs))
    for name, stats, *_ in searches:
        cells = "".join(f"{'%d / %d / %d' % stats[run] if run in stats else '-':>36s}" for run in runs)
        print(f"  {name:22s}{cells}")

    base = searches[0]
    for threshold in thresholds:
        print(f"\nExperiment-level identifications at q <= {threshold:g}, with entrapment FDP (combined)")
        print(f"  {'search':22s} {'precursors':>11s} {'entrap':>7s} {'FDP':>7s} {'vs base':>9s}"
              f"   {'peptides':>9s} {'entrap':>7s} {'FDP':>7s} {'vs base':>9s}   r")
        base_prec, _ = accepted(base[3], threshold)
        base_pep, _ = accepted(base[4], threshold)
        for name, _, ratio, precursors, peptides in searches:
            prec_t, prec_e = accepted(precursors, threshold)
            pep_t, pep_e = accepted(peptides, threshold)
            print(f"  {name:22s} {len(prec_t):11,d} {len(prec_e):7,d} "
                  f"{combined_fdp(len(prec_t), len(prec_e), ratio):7.2%} "
                  f"{len(prec_t) / max(len(base_prec), 1) - 1:+9.1%}   "
                  f"{len(pep_t):9,d} {len(pep_e):7,d} {combined_fdp(len(pep_t), len(pep_e), ratio):7.2%} "
                  f"{len(pep_t) / max(len(base_pep), 1) - 1:+9.1%}   {ratio:.4f}")

        print(f"\n  Target peptide overlap with {base[0]} at q <= {threshold:g}:")
        for name, _, _, _, peptides in searches[1:]:
            pep_t, _ = accepted(peptides, threshold)
            shared = len(pep_t & base_pep)
            print(f"    {name:22s} shared {shared:,}; only {name} {len(pep_t - base_pep):,}; "
                  f"only {base[0]} {len(base_pep - pep_t):,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
