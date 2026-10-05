#!/usr/bin/env python3
"""
Build-EntrapmentVariant.py

Derive an entrapment-ratio and/or decoy-stripped ("gendecoy") variant of an
existing Osprey spectral library, without Carafe or a GPU. Dataset-agnostic:
it works on any library directory in the Carafe entrapment layout, whatever
dataset it was built for.

Streams the spectral library one line at a time, so memory does not grow with
the (multi-GB) library. The pairing manifest (hundreds of MB) IS loaded, as a
sequence -> peptide_pair_index lookup.

-------------------------------------------------------------------------
Input directory layout (the Carafe entrapment library drop):

    carafe_spectral_library.tsv        spectral library (required)
    osprey_library_db_pairing.tsv      pairing manifest (required)
    osprey_library_db_peptides.fasta   peptide FASTA (optional; filtered
                                       the same way when present)

Anything else in the source directory (.libcache, PROVENANCE.txt, zips) is
NOT copied: a .libcache describes the source library, not the variant, and
Osprey rebuilds one on first use.

-------------------------------------------------------------------------
Row classes. Determined ENTIRELY from the ProteinID column:

    class               ProteinID shape
    ------------------- ---------------------------------------------
    target               sp|Q1XH10_pep00001|SKDA1_HUMAN
    entrapment           sp|Q1XH10_p_target_pep00001|SKDA1_HUMAN_p_target
    decoy of target      decoy_sp|Q1XH10_pep00001|SKDA1_HUMAN
    decoy of entrapment  decoy_sp|Q1XH10_p_target_pep00001|SKDA1_HUMAN_p_target

    A row is ENTRAPMENT-CLASS iff "_p_target" appears in ProteinID.
    A row is a DECOY iff ProteinID starts with "decoy_".

The library's `Decoy` column is 0 on EVERY row of these Carafe libraries.
Filtering on it is a silent no-op that yields a "gendecoy" library still full
of decoys. Never "fix" this to use the column; --gendecoy fails hard if it
drops no rows, so that mistake cannot pass unnoticed.

Manifest columns: sequence, decoy, proteins, peptide_type, peptide_pair_index.
The manifest's `proteins` lacks the `_pepNNNNN` infix, so library and manifest
join on sequence: library.StrippedPeptide == manifest.sequence.

-------------------------------------------------------------------------
Selection rule (which peptide_pair_index values keep their entrapment):

    keep(pair_index, r, salt) =
        int.from_bytes(blake2b((salt + str(pair_index)).encode(),
                               digest_size=8).digest(), "big") / 2**64 < r

Deterministic across processes and machines (unlike Python's builtin hash()),
and NESTED: at a fixed salt, the r=0.1 set is a subset of r=0.25 is a subset
of r=0.5, so a ratio series differs only by the entrapment added, never by a
reshuffle. A different salt gives an independent draw at the same ratio
(e.g. salt "b" built target+decoy+entrapment-r0.5b as a replicate of r0.5).
Because selection is per pair index, a --gendecoy variant at the same ratio
and salt carries exactly the same entrapment peptides as the libdecoy variant;
it does not need to be derived from it.

Per row:
    - Non-entrapment rows (target, decoy-of-target): always kept.
    - Entrapment-class rows (incl. decoy-of-entrapment): kept iff keep(...)
      for the row's pair index (looked up by sequence).
    - With --gendecoy, every decoy row is dropped (ProteinID starts with
      "decoy_"; in the manifest, decoy column == "Yes").

An entrapment-class sequence absent from the manifest cannot be assigned a
pair, so it is DROPPED (and reported) rather than leaking into every ratio.

This is the selection rule of the 2026-07-30 Build-EntrapmentVariants.py,
which built the SEA-AD ratio libraries in use; this script reproduces them
byte for byte. The older SEA-AD/tools/subset-entrapment-ratio.py used a seeded
random.shuffle (seed 2024) and selects an unrelated subset; it is retired.

-------------------------------------------------------------------------
Usage:

    # Build one variant (library + manifest + FASTA, streamed, + PROVENANCE.txt)
    python Build-EntrapmentVariant.py build --source-dir <r1.0 dir> \\
        --output-dir <dir> --ratio 0.1 [--salt ""] [--gendecoy]

    # Class counts for a library (one streaming pass), incl. entrapment rows
    # missing from the manifest
    python Build-EntrapmentVariant.py stats --source-dir <dir> [--report-file f]

    # Verify the nesting property from the manifest alone (no library scan)
    python Build-EntrapmentVariant.py check-nesting --source-dir <dir> \\
        --ratios 0.1,0.25,0.5 [--salt ""]

Each output file is written to a ".tmp" sibling and renamed into place only on
success, so an interrupted build cannot leave a truncated file that a later run
mistakes for complete. PROVENANCE.txt is written last; a directory without it
was not finished by this tool (or predates it).
"""

import argparse
import datetime
import hashlib
import os
import subprocess
import sys
import time

TOOL_VERSION = "1.0"

LIB_FILENAME = "carafe_spectral_library.tsv"
PAIRING_FILENAME = "osprey_library_db_pairing.tsv"
FASTA_FILENAME = "osprey_library_db_peptides.fasta"
PROVENANCE_FILENAME = "PROVENANCE.txt"

PROGRESS_EVERY = 5_000_000  # library rows between progress prints


# --------------------------------------------------------------------------
# Core selection rule
# --------------------------------------------------------------------------

def keep(pair_index, r, salt=""):
    """Stable (process-independent) decision for whether a peptide_pair_index
    keeps its entrapment at ratio r with the given salt."""
    if r >= 1.0:
        return True
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
    """sequence -> peptide_pair_index for ALL manifest rows. Returns
    (dict, conflicts): conflicts counts sequences seen again with a DIFFERENT
    pair index (first occurrence wins; should be ~0)."""
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
    """Distinct peptide_pair_index values of entrapment-class manifest rows -
    the set the ratio/salt selection is applied over."""
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
# stats: one streaming pass over a library
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

    print(f"[stats] done: {n:,} rows in {time.time() - t0:.1f}s", flush=True)

    n_target_pep = len(peptides["target"])
    n_entrap_pep = len(peptides["entrapment"])
    ratio = (n_entrap_pep / n_target_pep) if n_target_pep else float("nan")

    lines = ["# Library class counts", "",
             "| class | distinct peptides | rows |", "|---|---:|---:|"]
    for c in classes:
        lines.append(f"| {c} | {len(peptides[c]):,} | {rows[c]:,} |")
    lines += ["",
              f"Entrapment:target peptide ratio (distinct peptides, non-decoy classes) "
              f"= {n_entrap_pep:,} / {n_target_pep:,} = {ratio:.6f}",
              "",
              f"Manifest sequence-lookup conflicts (same sequence, different pair_index; "
              f"first occurrence used): {conflicts}",
              "",
              f"Entrapment-class rows whose StrippedPeptide has NO manifest match: "
              f"{unmatched_row_count:,} rows, {len(unmatched_entrapment_seqs):,} distinct sequences",
              f"Examples: {unmatched_examples}",
              "",
              "Unmatched entrapment-class rows are DROPPED from every built variant."]
    report = "\n".join(lines)
    print(report)

    if args.report_file:
        d = os.path.dirname(args.report_file)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(args.report_file, "w", encoding="utf-8") as f:
            f.write(report + "\n")
        print(f"[stats] wrote {args.report_file}", flush=True)


# --------------------------------------------------------------------------
# build: filter library + pairing manifest + fasta into one variant
# --------------------------------------------------------------------------

class _AtomicWriter:
    """Write to <path>.tmp, rename into place on success, delete on failure."""

    def __init__(self, final_path):
        self.final_path = final_path
        self.tmp_path = final_path + ".tmp"

    def __enter__(self):
        self.f = open(self.tmp_path, "w", encoding="utf-8", newline="")
        return self.f

    def __exit__(self, exc_type, exc, tb):
        self.f.close()
        if exc_type is None:
            os.replace(self.tmp_path, self.final_path)
        else:
            try:
                os.remove(self.tmp_path)
            except OSError:
                pass
        return False


def filter_library(lib_path, out_path, seq_to_pair, r, salt, gendecoy):
    rows_written = 0
    n = 0
    decoys_dropped = 0
    kept_pair_indices = set()
    entrapment_peptides_kept = set()
    target_peptides_kept = set()
    unmatched_examples = []
    unmatched_count = 0
    t0 = time.time()
    with _AtomicWriter(out_path) as fout, open(lib_path, "r", encoding="utf-8") as fin:
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
                decoys_dropped += 1
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
                # Count only NON-decoy entrapment: "_p_target" matches the decoy of
                # an entrapment peptide too, and counting both roughly doubles the
                # reported ratio (r0.5 read as 0.967). The denominator excludes
                # decoys, so the numerator must as well.
                if not decoy:
                    entrapment_peptides_kept.add(stripped)
            elif not decoy:
                target_peptides_kept.add(stripped)

            fout.write(line)
            rows_written += 1

            if n % PROGRESS_EVERY == 0:
                print(f"[build]   library: {n:,} rows read, {rows_written:,} written "
                      f"({time.time() - t0:.0f}s elapsed)", flush=True)

        if gendecoy and decoys_dropped == 0:
            # Raising inside the writer discards the .tmp file.
            raise SystemExit(
                f"ERROR: --gendecoy dropped no rows: no ProteinID in {lib_path} starts with "
                f"'decoy_'. The output would NOT be a gendecoy library. Check the source.")
    return {
        "rows_read": n,
        "rows_written": rows_written,
        "decoys_dropped": decoys_dropped,
        "kept_pair_indices": len(kept_pair_indices),
        "entrapment_peptides_kept": len(entrapment_peptides_kept),
        "target_peptides_kept": len(target_peptides_kept),
        "unmatched_count": unmatched_count,
        "unmatched_examples": unmatched_examples,
    }


def filter_pairing(pairing_path, out_path, r, salt, gendecoy):
    rows_written = 0
    n = 0
    with _AtomicWriter(out_path) as fout, open(pairing_path, "r", encoding="utf-8") as fin:
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
            if gendecoy and parts[decoy_i].strip().lower() == "yes":
                continue
            if is_entrapment_protein(parts[proteins_i]) and not keep(parts[pair_i], r, salt):
                continue
            fout.write(line)
            rows_written += 1
    return {"rows_read": n, "rows_written": rows_written}


def _fasta_records(fasta_path):
    """Yield (header_without_gt, [sequence_lines]); tolerates multi-line records."""
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
    records_written = 0
    n = 0
    unmatched_count = 0
    with _AtomicWriter(out_path) as fout:
        for protein_id, seq_lines in _fasta_records(fasta_path):
            n += 1
            if gendecoy and is_decoy_protein(protein_id):
                continue
            if is_entrapment_protein(protein_id):
                pair_index = seq_to_pair.get("".join(seq_lines))
                if pair_index is None:
                    unmatched_count += 1
                    continue
                if not keep(pair_index, r, salt):
                    continue
            fout.write(">" + protein_id + "\n")
            for sl in seq_lines:
                fout.write(sl + "\n")
            records_written += 1
    return {"records_read": n, "records_written": records_written, "unmatched_count": unmatched_count}


def _tool_revision():
    """Git commit of the checkout holding this script, if it is one."""
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        out = subprocess.run(["git", "-C", here, "log", "-1", "--format=%h %cs", "--", os.path.basename(__file__)],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def _describe_file(path):
    st = os.stat(path)
    mtime = datetime.datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds")
    return f"{os.path.basename(path)}  {st.st_size:,} bytes  modified {mtime}"


def write_provenance(args, source_files, summary):
    lines = [
        f"Entrapment variant derived by Build-EntrapmentVariant.py {TOOL_VERSION} "
        f"(ai/scripts/Osprey/Library, last changed {_tool_revision()})",
        "",
        f"Built      : {datetime.datetime.now().isoformat(timespec='seconds')}",
        f"Source dir : {os.path.abspath(args.source_dir)}",
    ]
    for p in source_files:
        lines.append(f"             {_describe_file(p)}")
    lines += [
        f"Ratio      : {args.ratio}  (fraction of pair indices that keep their entrapment)",
        f"Salt       : {args.salt!r}",
        f"Decoys     : {'STRIPPED (gendecoy: Osprey generates its own)' if args.gendecoy else 'kept from the source library (libdecoy)'}",
        f"Selection  : blake2b(salt + pair_index) / 2^64 < ratio; nested across ratios at one salt",
        "",
        f"Library    : {summary['library_rows_written']:,} rows written",
        f"Peptides   : {summary['target_peptides_kept']:,} target, "
        f"{summary['entrapment_peptides_kept']:,} entrapment "
        f"(realized ratio {summary['realized_ratio']:.6f})",
        f"Pairs kept : {summary['kept_pair_indices']:,} entrapment pair indices",
        f"Manifest   : {summary['pairing_rows_written']:,} rows written",
        f"FASTA      : {summary['fasta']}",
        f"Unmatched  : {summary['unmatched_count']:,} entrapment-class library rows absent "
        f"from the manifest, dropped",
        "",
        "Rebuild:",
        f"  python Build-EntrapmentVariant.py build --source-dir \"{os.path.abspath(args.source_dir)}\" "
        f"--output-dir \"{os.path.abspath(args.output_dir)}\" --ratio {args.ratio} --salt \"{args.salt}\""
        + (" --gendecoy" if args.gendecoy else ""),
        "",
        "Guide: ai/docs/osprey-library-generation-guide.md (Derivation)",
    ]
    path = os.path.join(args.output_dir, PROVENANCE_FILENAME)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines) + "\n")
    return path


def cmd_build(args):
    if not (0.0 < args.ratio <= 1.0):
        sys.exit(f"ERROR: --ratio must be in (0, 1]; got {args.ratio}")
    if os.path.abspath(args.source_dir) == os.path.abspath(args.output_dir):
        sys.exit("ERROR: --output-dir must differ from --source-dir")

    lib_path = os.path.join(args.source_dir, LIB_FILENAME)
    pairing_path = os.path.join(args.source_dir, PAIRING_FILENAME)
    fasta_path = os.path.join(args.source_dir, FASTA_FILENAME)
    for p in (lib_path, pairing_path):
        if not os.path.isfile(p):
            sys.exit(f"ERROR: source file not found: {p}")
    has_fasta = os.path.isfile(fasta_path)

    os.makedirs(args.output_dir, exist_ok=True)
    # A stale PROVENANCE.txt must not vouch for a half-rebuilt directory.
    try:
        os.remove(os.path.join(args.output_dir, PROVENANCE_FILENAME))
    except OSError:
        pass

    print(f"[build] ratio={args.ratio} salt={args.salt!r} gendecoy={args.gendecoy} "
          f"-> {args.output_dir}", flush=True)

    t0 = time.time()
    seq_to_pair, conflicts = load_pairing_seq_to_pair(pairing_path)
    print(f"[build] loaded {len(seq_to_pair):,} manifest sequences ({conflicts} conflicts) "
          f"in {time.time() - t0:.1f}s", flush=True)

    t0 = time.time()
    lib = filter_library(lib_path, os.path.join(args.output_dir, LIB_FILENAME),
                         seq_to_pair, args.ratio, args.salt, args.gendecoy)
    print(f"[build] library: {lib['rows_written']:,} / {lib['rows_read']:,} rows written "
          f"in {time.time() - t0:.1f}s", flush=True)
    if lib["unmatched_count"]:
        print(f"[build] WARNING: {lib['unmatched_count']:,} entrapment-class library rows had no "
              f"manifest match and were DROPPED. Examples: {lib['unmatched_examples']}", flush=True)

    t0 = time.time()
    pairing = filter_pairing(pairing_path, os.path.join(args.output_dir, PAIRING_FILENAME),
                             args.ratio, args.salt, args.gendecoy)
    print(f"[build] manifest: {pairing['rows_written']:,} / {pairing['rows_read']:,} rows written "
          f"in {time.time() - t0:.1f}s", flush=True)

    if has_fasta:
        t0 = time.time()
        fasta = filter_fasta(fasta_path, os.path.join(args.output_dir, FASTA_FILENAME),
                             seq_to_pair, args.ratio, args.salt, args.gendecoy)
        fasta_desc = f"{fasta['records_written']:,} / {fasta['records_read']:,} records written"
        print(f"[build] fasta: {fasta_desc} in {time.time() - t0:.1f}s", flush=True)
    else:
        fasta_desc = "none in the source directory"
        print(f"[build] no {FASTA_FILENAME} in the source; skipped", flush=True)

    realized = (lib["entrapment_peptides_kept"] / lib["target_peptides_kept"]
                if lib["target_peptides_kept"] else float("nan"))
    summary = {
        "library_rows_written": lib["rows_written"],
        "target_peptides_kept": lib["target_peptides_kept"],
        "entrapment_peptides_kept": lib["entrapment_peptides_kept"],
        "realized_ratio": realized,
        "kept_pair_indices": lib["kept_pair_indices"],
        "pairing_rows_written": pairing["rows_written"],
        "fasta": fasta_desc,
        "unmatched_count": lib["unmatched_count"],
    }
    source_files = [lib_path, pairing_path] + ([fasta_path] if has_fasta else [])
    prov = write_provenance(args, source_files, summary)
    print(f"[build] realized entrapment:target peptide ratio = "
          f"{lib['entrapment_peptides_kept']:,} / {lib['target_peptides_kept']:,} = {realized:.6f}",
          flush=True)
    print(f"[build] wrote {prov}", flush=True)


# --------------------------------------------------------------------------
# check-nesting: verify the kept pair-index sets nest across ratios
# --------------------------------------------------------------------------

def cmd_check_nesting(args):
    pairing_path = os.path.join(args.source_dir, PAIRING_FILENAME)
    ratios = sorted(float(x) for x in args.ratios.split(","))
    universe = load_pairing_pair_index_universe(pairing_path)
    print(f"[check-nesting] {len(universe):,} distinct entrapment pair indices in {pairing_path}", flush=True)

    selected = {}
    for r in ratios:
        selected[r] = {p for p in universe if keep(p, r, args.salt)}
        print(f"[check-nesting] r={r}: {len(selected[r]):,} selected "
              f"({len(selected[r]) / len(universe):.4f})", flush=True)

    ok = True
    for lo, hi in zip(ratios, ratios[1:]):
        is_subset = selected[lo].issubset(selected[hi])
        print(f"[check-nesting] r{lo} subset of r{hi}: {is_subset}", flush=True)
        ok = ok and is_subset
    print(f"[check-nesting] NESTING HOLDS: {ok}", flush=True)
    if not ok:
        sys.exit(1)


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    ap_build = sub.add_parser("build", help="Build one variant.")
    ap_build.add_argument("--source-dir", required=True,
                          help="library directory to derive from (normally the r=1.0 drop)")
    ap_build.add_argument("--output-dir", required=True)
    ap_build.add_argument("--ratio", type=float, required=True,
                          help="fraction of entrapment pairs to keep, in (0, 1]")
    ap_build.add_argument("--salt", default="",
                          help="selection salt; a different salt is an independent draw (default '')")
    ap_build.add_argument("--gendecoy", action="store_true",
                          help="drop every decoy row (ProteinID 'decoy_' prefix; manifest decoy == Yes)")
    ap_build.set_defaults(func=cmd_build)

    ap_stats = sub.add_parser("stats", help="Report library class counts (one streaming pass).")
    ap_stats.add_argument("--source-dir", required=True)
    ap_stats.add_argument("--report-file", default=None)
    ap_stats.set_defaults(func=cmd_stats)

    ap_nest = sub.add_parser("check-nesting", help="Verify kept pair-index sets nest across ratios.")
    ap_nest.add_argument("--source-dir", required=True)
    ap_nest.add_argument("--ratios", default="0.1,0.25,0.5")
    ap_nest.add_argument("--salt", default="")
    ap_nest.set_defaults(func=cmd_check_nesting)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
