#!/usr/bin/env python
"""
Build-EntrapmentVariants.py

Build entrapment-ratio variants of an Osprey spectral library by
streaming-filtering large TSV/FASTA files. Never loads the (multi-GB)
spectral library into memory - reads and writes it one line at a time.
The pairing manifest (hundreds of MB) IS loaded into memory as a
sequence -> peptide_pair_index lookup.

-------------------------------------------------------------------------
Library format (tab-separated, header row). Row class is determined
ENTIRELY from the ProteinID column:

    class               ProteinID shape
    ------------------- ---------------------------------------------
    target               sp|Q1XH10_pep00001|SKDA1_HUMAN
    entrapment            sp|Q1XH10_p_target_pep00001|SKDA1_HUMAN_p_target
    decoy of target       decoy_sp|Q1XH10_pep00001|SKDA1_HUMAN
    decoy of entrapment   decoy_sp|Q1XH10_p_target_pep00001|SKDA1_HUMAN_p_target

    A row is ENTRAPMENT-CLASS iff "_p_target" appears in ProteinID.
    A row is a DECOY iff ProteinID starts with "decoy_".
    These two facts are independent (2x2).

Pairing manifest columns: sequence, decoy, proteins, peptide_type,
peptide_pair_index. The manifest's `proteins` string lacks the
`_pepNNNNN` infix the library's ProteinID has, so the join between
library and manifest is on peptide sequence:
    library.StrippedPeptide == manifest.sequence

FASTA headers carry the same ProteinID shapes as the library, one
sequence line following each header (defensively coded to also handle
multi-line sequence blocks, i.e. everything up to the next '>').

-------------------------------------------------------------------------
Selection rule (which peptide_pair_index values are "in"):

    stable_hash(pair_index, r, salt) = True iff
        int.from_bytes(blake2b((salt + str(pair_index)).encode(), digest_size=8).digest(), "big") / 2**64 < r

This is deterministic across processes/runs (unlike Python's salted
builtin hash()). Per row:

    - Non-entrapment rows (target, decoy-of-target): ALWAYS kept.
    - Entrapment-class rows (incl. decoy-of-entrapment): kept iff the
      row's peptide_pair_index (looked up via sequence in the pairing
      manifest) is selected by stable_hash(pair_index, r, salt).
    - For a -gendecoy variant, additionally drop EVERY row whose
      ProteinID/proteins string starts with "decoy_" (or, for the
      manifest, whose `decoy` column is "Yes").

An entrapment-class sequence with NO match in the pairing manifest
cannot have its pair membership determined, so it is DROPPED (not
kept) and counted/reported separately. This choice is deliberate: a
row we can't classify should not silently leak into every variant
(which is what "always keep on no-match" would do).

-------------------------------------------------------------------------
Usage:

    # One streaming pass over the base library to report class counts
    # (rows + distinct peptides) for target / entrapment / decoy-of-target
    # / decoy-of-entrapment, and to find entrapment sequences absent from
    # the pairing manifest.
    python Build-EntrapmentVariants.py stats \
        --source-dir "D:\\test\\osprey-runs\\sea-ad\\lib\\target+decoy+entrapment"

    # Build one variant (library + pairing manifest + fasta, streamed).
    python Build-EntrapmentVariants.py build \
        --source-dir "D:\\test\\osprey-runs\\sea-ad\\lib\\target+decoy+entrapment" \
        --output-dir "D:\\test\\osprey-runs\\sea-ad\\lib\\target+decoy+entrapment-r0.5" \
        --ratio 0.5 --salt "" [--gendecoy]

    # Verify the nesting property (r0.1 subset of r0.25 subset of r0.5)
    # from the manifest's pair-index universe alone (fast - no library scan).
    python Build-EntrapmentVariants.py check-nesting \
        --source-dir "D:\\test\\osprey-runs\\sea-ad\\lib\\target+decoy+entrapment" \
        --ratios 0.1,0.25,0.5 --salt ""

Python 3. Streams the spectral library line-by-line; only the pairing
manifest (and, for `stats`, the small per-class distinct-peptide sets)
are held in memory. Each output file is written to a ".tmp" sibling and
atomically renamed into place only on success, so an interrupted run
cannot leave a truncated file that a later run mistakes for complete.
"""

import argparse
import hashlib
import os
import sys
import time

LIB_FILENAME = "carafe_spectral_library.tsv"
PAIRING_FILENAME = "osprey_library_db_pairing.tsv"
FASTA_FILENAME = "osprey_library_db_peptides.fasta"

PROGRESS_EVERY = 5_000_000  # library rows between progress prints


# --------------------------------------------------------------------------
# Core selection rule
# --------------------------------------------------------------------------

def keep(pair_index, r, salt=""):
    """Stable (process-independent) hash decision for whether a
    peptide_pair_index is selected at ratio r with the given salt."""
    h = hashlib.blake2b((salt + str(pair_index)).encode(), digest_size=8).digest()
    return int.from_bytes(h, "big") / 2**64 < r


def is_entrapment_protein(protein_id):
    return "_p_target" in protein_id


def is_decoy_protein(protein_id):
    return protein_id.startswith("decoy_")


# --------------------------------------------------------------------------
# Pairing manifest
# --------------------------------------------------------------------------

def load_pairing_seq_to_pair(pairing_path):
    """Build sequence -> peptide_pair_index for ALL manifest rows.
    Returns (dict, conflict_count) where conflict_count is the number of
    sequences that appeared more than once in the manifest mapping to
    DIFFERENT pair indices (first occurrence wins; should be ~0)."""
    seq_to_pair = {}
    conflicts = 0
    with open(pairing_path, "r", encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        seq_i = idx["sequence"]
        pair_i = idx["peptide_pair_index"]
        for line in f:
            if not line:
                continue
            parts = line.rstrip("\n").split("\t")
            seq = parts[seq_i]
            pair_index = parts[pair_i]
            prev = seq_to_pair.get(seq)
            if prev is None:
                seq_to_pair[seq] = pair_index
            elif prev != pair_index:
                conflicts += 1
    return seq_to_pair, conflicts


def load_pairing_pair_index_universe(pairing_path):
    """Fast pass collecting the distinct set of peptide_pair_index values
    that belong to entrapment-class manifest rows (i.e. the set of pair
    indices the ratio/salt selection is actually applied over)."""
    universe = set()
    with open(pairing_path, "r", encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        proteins_i = idx["proteins"]
        pair_i = idx["peptide_pair_index"]
        for line in f:
            if not line:
                continue
            parts = line.rstrip("\n").split("\t")
            if is_entrapment_protein(parts[proteins_i]):
                universe.add(parts[pair_i])
    return universe


# --------------------------------------------------------------------------
# stats: one streaming pass over the base library
# --------------------------------------------------------------------------

def cmd_stats(args):
    lib_path = os.path.join(args.source_dir, LIB_FILENAME)
    pairing_path = os.path.join(args.source_dir, PAIRING_FILENAME)

    print(f"[stats] loading pairing manifest sequence lookup from {pairing_path} ...", flush=True)
    t0 = time.time()
    seq_to_pair, conflicts = load_pairing_seq_to_pair(pairing_path)
    print(f"[stats] loaded {len(seq_to_pair):,} manifest sequences "
          f"({conflicts} sequence(s) mapped to conflicting pair indices) "
          f"in {time.time() - t0:.1f}s", flush=True)

    classes = ("target", "entrapment", "decoy_target", "decoy_entrapment")
    rows = {c: 0 for c in classes}
    peptides = {c: set() for c in classes}

    unmatched_entrapment_seqs = set()
    unmatched_examples = []
    unmatched_row_count = 0

    print(f"[stats] streaming {lib_path} ...", flush=True)
    t0 = time.time()
    n = 0
    with open(lib_path, "r", encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        protein_i = header.index("ProteinID")
        stripped_i = header.index("StrippedPeptide")
        for line in f:
            n += 1
            parts = line.split("\t")
            protein_id = parts[protein_i]
            stripped = parts[stripped_i]
            entrap = is_entrapment_protein(protein_id)
            decoy = is_decoy_protein(protein_id)
            if entrap and decoy:
                c = "decoy_entrapment"
            elif entrap:
                c = "entrapment"
            elif decoy:
                c = "decoy_target"
            else:
                c = "target"
            rows[c] += 1
            peptides[c].add(stripped)

            if entrap and stripped not in seq_to_pair:
                unmatched_row_count += 1
                if stripped not in unmatched_entrapment_seqs:
                    unmatched_entrapment_seqs.add(stripped)
                    if len(unmatched_examples) < 3:
                        unmatched_examples.append(stripped)

            if n % PROGRESS_EVERY == 0:
                print(f"[stats]   {n:,} rows ({time.time() - t0:.0f}s elapsed)", flush=True)

    elapsed = time.time() - t0
    print(f"[stats] done: {n:,} rows in {elapsed:.1f}s", flush=True)

    n_target_pep = len(peptides["target"])
    n_entrap_pep = len(peptides["entrapment"])
    ratio = (n_entrap_pep / n_target_pep) if n_target_pep else float("nan")

    lines = []
    lines.append("# Base library class counts\n")
    lines.append("")
    lines.append("| class | distinct peptides | rows |")
    lines.append("|---|---:|---:|")
    for c in classes:
        lines.append(f"| {c} | {len(peptides[c]):,} | {rows[c]:,} |")
    lines.append("")
    lines.append(f"Base entrapment:target peptide ratio (distinct peptides, "
                  f"non-decoy classes only) = {n_entrap_pep:,} / {n_target_pep:,} "
                  f"= {ratio:.6f}")
    lines.append("")
    lines.append(f"Manifest sequence-lookup conflicts (same sequence, different "
                  f"pair_index; first occurrence used): {conflicts}")
    lines.append("")
    lines.append(f"Library entrapment-class rows whose StrippedPeptide has NO "
                  f"match in the pairing manifest: {unmatched_row_count:,} rows, "
                  f"{len(unmatched_entrapment_seqs):,} distinct sequences")
    lines.append(f"Examples: {unmatched_examples}")
    lines.append("")
    lines.append("Decision: unmatched entrapment-class rows are DROPPED from every "
                  "variant (their pair membership can't be determined, so they must "
                  "not silently pass through into all ratios).")
    report = "\n".join(lines)
    print(report)

    if args.report_file:
        os.makedirs(os.path.dirname(args.report_file), exist_ok=True)
        with open(args.report_file, "w", encoding="utf-8") as f:
            f.write(report + "\n")
        print(f"[stats] wrote {args.report_file}", flush=True)

    return {
        "rows": rows,
        "peptides": {c: len(peptides[c]) for c in classes},
        "ratio": ratio,
        "conflicts": conflicts,
        "unmatched_rows": unmatched_row_count,
        "unmatched_seqs": len(unmatched_entrapment_seqs),
        "unmatched_examples": unmatched_examples,
    }


# --------------------------------------------------------------------------
# build: filter library + pairing manifest + fasta into one variant
# --------------------------------------------------------------------------

def _atomic_write_open(final_path):
    tmp_path = final_path + ".tmp"
    return tmp_path, open(tmp_path, "w", encoding="utf-8", newline="")


def _atomic_finish(tmp_path, final_path):
    os.replace(tmp_path, final_path)


def filter_library(lib_path, out_path, seq_to_pair, r, salt, gendecoy):
    tmp_path, fout = _atomic_write_open(out_path)
    rows_written = 0
    n = 0
    kept_pair_indices = set()
    entrapment_peptides_kept = set()
    target_peptides_kept = set()
    unmatched_examples = []
    unmatched_count = 0
    t0 = time.time()
    try:
        with open(lib_path, "r", encoding="utf-8") as fin:
            header_line = fin.readline()
            fout.write(header_line)
            header = header_line.rstrip("\n").split("\t")
            protein_i = header.index("ProteinID")
            stripped_i = header.index("StrippedPeptide")
            for line in fin:
                n += 1
                parts = line.split("\t")
                protein_id = parts[protein_i]
                stripped = parts[stripped_i]

                decoy = is_decoy_protein(protein_id)
                if gendecoy and decoy:
                    continue

                if is_entrapment_protein(protein_id):
                    pair_index = seq_to_pair.get(stripped)
                    if pair_index is None:
                        unmatched_count += 1
                        if len(unmatched_examples) < 3:
                            unmatched_examples.append(stripped)
                        continue
                    if not keep(pair_index, r, salt):
                        continue
                    kept_pair_indices.add(pair_index)
                    # Count only NON-decoy entrapment here. is_entrapment_protein
                    # matches "_p_target" whether or not the row is a decoy, so
                    # counting every entrapment-class row lumps a peptide together
                    # with its decoy and roughly DOUBLES the reported ratio - which
                    # made r0.5 read as 0.967 instead of its true 0.4996. The
                    # denominator (target_peptides_kept) already excludes decoys,
                    # so both sides must.
                    if not decoy:
                        entrapment_peptides_kept.add(stripped)
                else:
                    if not decoy:
                        target_peptides_kept.add(stripped)

                fout.write(line)
                rows_written += 1

                if n % PROGRESS_EVERY == 0:
                    print(f"[build]   library: {n:,} rows read, {rows_written:,} written "
                          f"({time.time() - t0:.0f}s elapsed)", flush=True)
    except BaseException:
        fout.close()
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    fout.close()
    _atomic_finish(tmp_path, out_path)
    return {
        "rows_read": n,
        "rows_written": rows_written,
        "kept_pair_indices": kept_pair_indices,
        "entrapment_peptides_kept": len(entrapment_peptides_kept),
        "target_peptides_kept": len(target_peptides_kept),
        "unmatched_count": unmatched_count,
        "unmatched_examples": unmatched_examples,
    }


def filter_pairing(pairing_path, out_path, r, salt, gendecoy):
    tmp_path, fout = _atomic_write_open(out_path)
    rows_written = 0
    n = 0
    try:
        with open(pairing_path, "r", encoding="utf-8") as fin:
            header_line = fin.readline()
            fout.write(header_line)
            header = header_line.rstrip("\n").split("\t")
            idx = {name: i for i, name in enumerate(header)}
            proteins_i = idx["proteins"]
            decoy_i = idx["decoy"]
            pair_i = idx["peptide_pair_index"]
            for line in fin:
                n += 1
                parts = line.rstrip("\n").split("\t")
                is_decoy_row = parts[decoy_i].strip().lower() == "yes"
                if gendecoy and is_decoy_row:
                    continue
                if is_entrapment_protein(parts[proteins_i]):
                    pair_index = parts[pair_i]
                    if not keep(pair_index, r, salt):
                        continue
                fout.write(line)
                rows_written += 1
    except BaseException:
        fout.close()
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    fout.close()
    _atomic_finish(tmp_path, out_path)
    return {"rows_read": n, "rows_written": rows_written}


def _fasta_records(fasta_path):
    """Yield (header_line_no_gt_no_newline, [sequence_lines]) tuples."""
    header = None
    seq_lines = []
    with open(fasta_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if header is not None:
                    yield header, seq_lines
                header = line[1:]
                seq_lines = []
            else:
                seq_lines.append(line)
        if header is not None:
            yield header, seq_lines


def filter_fasta(fasta_path, out_path, seq_to_pair, r, salt, gendecoy):
    tmp_path, fout = _atomic_write_open(out_path)
    records_written = 0
    n = 0
    unmatched_count = 0
    try:
        for protein_id, seq_lines in _fasta_records(fasta_path):
            n += 1
            decoy = is_decoy_protein(protein_id)
            if gendecoy and decoy:
                continue
            if is_entrapment_protein(protein_id):
                seq = "".join(seq_lines)
                pair_index = seq_to_pair.get(seq)
                if pair_index is None:
                    unmatched_count += 1
                    continue
                if not keep(pair_index, r, salt):
                    continue
            fout.write(">" + protein_id + "\n")
            for sl in seq_lines:
                fout.write(sl + "\n")
            records_written += 1
    except BaseException:
        fout.close()
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    fout.close()
    _atomic_finish(tmp_path, out_path)
    return {"records_read": n, "records_written": records_written, "unmatched_count": unmatched_count}


def cmd_build(args):
    lib_path = os.path.join(args.source_dir, LIB_FILENAME)
    pairing_path = os.path.join(args.source_dir, PAIRING_FILENAME)
    fasta_path = os.path.join(args.source_dir, FASTA_FILENAME)
    for p in (lib_path, pairing_path, fasta_path):
        if not os.path.isfile(p):
            print(f"ERROR: source file not found: {p}", file=sys.stderr)
            sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"[build] ratio={args.ratio} salt={args.salt!r} gendecoy={args.gendecoy} "
          f"-> {args.output_dir}", flush=True)

    print(f"[build] loading pairing manifest sequence lookup ...", flush=True)
    t0 = time.time()
    seq_to_pair, conflicts = load_pairing_seq_to_pair(pairing_path)
    print(f"[build] loaded {len(seq_to_pair):,} sequences ({conflicts} conflicts) "
          f"in {time.time() - t0:.1f}s", flush=True)

    out_lib = os.path.join(args.output_dir, LIB_FILENAME)
    out_pairing = os.path.join(args.output_dir, PAIRING_FILENAME)
    out_fasta = os.path.join(args.output_dir, FASTA_FILENAME)

    t0 = time.time()
    lib_stats = filter_library(lib_path, out_lib, seq_to_pair, args.ratio, args.salt, args.gendecoy)
    lib_elapsed = time.time() - t0
    print(f"[build] library: {lib_stats['rows_written']:,} / {lib_stats['rows_read']:,} rows written "
          f"in {lib_elapsed:.1f}s", flush=True)
    if lib_stats["unmatched_count"]:
        print(f"[build] WARNING: {lib_stats['unmatched_count']:,} library entrapment rows had no "
              f"manifest match and were DROPPED. Examples: {lib_stats['unmatched_examples']}", flush=True)

    t0 = time.time()
    pairing_stats = filter_pairing(pairing_path, out_pairing, args.ratio, args.salt, args.gendecoy)
    print(f"[build] pairing: {pairing_stats['rows_written']:,} / {pairing_stats['rows_read']:,} rows written "
          f"in {time.time() - t0:.1f}s", flush=True)

    t0 = time.time()
    fasta_stats = filter_fasta(fasta_path, out_fasta, seq_to_pair, args.ratio, args.salt, args.gendecoy)
    print(f"[build] fasta: {fasta_stats['records_written']:,} / {fasta_stats['records_read']:,} records written "
          f"in {time.time() - t0:.1f}s", flush=True)

    ratio_realized = (lib_stats["entrapment_peptides_kept"] / lib_stats["target_peptides_kept"]
                       if lib_stats["target_peptides_kept"] else float("nan"))

    summary = {
        "output_dir": args.output_dir,
        "ratio": args.ratio,
        "salt": args.salt,
        "gendecoy": args.gendecoy,
        "library_rows_written": lib_stats["rows_written"],
        "entrapment_peptides_kept": lib_stats["entrapment_peptides_kept"],
        "target_peptides_kept": lib_stats["target_peptides_kept"],
        "realized_entrapment_target_ratio": ratio_realized,
        "kept_pair_indices": lib_stats["kept_pair_indices"],
        "unmatched_count": lib_stats["unmatched_count"],
        "pairing_rows_written": pairing_stats["rows_written"],
        "fasta_records_written": fasta_stats["records_written"],
    }
    print(f"[build] realized entrapment:target peptide ratio = "
          f"{lib_stats['entrapment_peptides_kept']:,} / {lib_stats['target_peptides_kept']:,} "
          f"= {ratio_realized:.6f}", flush=True)
    return summary


# --------------------------------------------------------------------------
# check-nesting: verify r0.1 subset r0.25 subset r0.5 (same salt) purely
# from the manifest's entrapment pair-index universe (fast, no library scan)
# --------------------------------------------------------------------------

def cmd_check_nesting(args):
    pairing_path = os.path.join(args.source_dir, PAIRING_FILENAME)
    ratios = sorted(float(x) for x in args.ratios.split(","))
    print(f"[check-nesting] loading entrapment pair-index universe from {pairing_path} ...", flush=True)
    universe = load_pairing_pair_index_universe(pairing_path)
    print(f"[check-nesting] {len(universe):,} distinct entrapment peptide_pair_index values", flush=True)

    selected = {}
    for r in ratios:
        sel = {p for p in universe if keep(p, r, args.salt)}
        selected[r] = sel
        print(f"[check-nesting] r={r}: {len(sel):,} / {len(universe):,} pair indices selected "
              f"({len(sel)/len(universe):.4f})", flush=True)

    ok = True
    for i in range(len(ratios) - 1):
        lo, hi = ratios[i], ratios[i + 1]
        is_subset = selected[lo].issubset(selected[hi])
        print(f"[check-nesting] r{lo} subset of r{hi}: {is_subset}", flush=True)
        ok = ok and is_subset

    print(f"[check-nesting] NESTING HOLDS: {ok}", flush=True)
    return ok


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    ap_stats = sub.add_parser("stats", help="Report base-library class counts (one streaming pass).")
    ap_stats.add_argument("--source-dir", required=True)
    ap_stats.add_argument("--report-file", default=None)
    ap_stats.set_defaults(func=cmd_stats)

    ap_build = sub.add_parser("build", help="Build one entrapment-ratio variant.")
    ap_build.add_argument("--source-dir", required=True)
    ap_build.add_argument("--output-dir", required=True)
    ap_build.add_argument("--ratio", type=float, required=True)
    ap_build.add_argument("--salt", default="")
    ap_build.add_argument("--gendecoy", action="store_true",
                           help="Drop every row/record whose ProteinID starts with decoy_ "
                                "(or manifest decoy column == Yes).")
    ap_build.set_defaults(func=cmd_build)

    ap_nest = sub.add_parser("check-nesting", help="Verify kept pair-index sets nest across ratios.")
    ap_nest.add_argument("--source-dir", required=True)
    ap_nest.add_argument("--ratios", default="0.1,0.25,0.5")
    ap_nest.add_argument("--salt", default="")
    ap_nest.set_defaults(func=cmd_check_nesting)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
