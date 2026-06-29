#!/usr/bin/env python3
"""Parse a samply Gecko-format profile JSON into a flat per-function CSV.

Usage: samply-to-csv.py <profile.json> [out.csv] [--binary <elf>]

If samply could not resolve symbols at record time (typical when
--save-only is used), function names appear as raw hex addresses
(e.g. ``0x1268cf``). Pass ``--binary <elf>`` and the script will
call ``addr2line -e <elf> -f`` to resolve each address, then
demangle the result via ``c++filt`` (handles both Itanium C++ and
Rust v0 mangling on binutils >= 2.36).

Output CSV columns: function, own_ms, total_ms

Notes
-----
samply >= 0.13 uses ``stringArray`` (not the older ``stringTable``)
and weights samples by ``threadCPUDelta`` in microseconds. We
convert that to milliseconds.

Multi-thread aggregation: we sum CPU time across every thread that
ran the same function, so a parallel SVM training shows up as the
total CPU it consumed (matches what dotTrace's Reporter.exe XML
gives on the C# side).

A function is counted at most ONCE per sample for its ``total_ms``
tally even when it appears multiple times in the stack (recursion),
matching dotTrace's TotalTime accounting.
"""
import argparse
import gzip
import json
import os
import re
import subprocess
import sys
from collections import defaultdict


HEX_RE = re.compile(r"^0x[0-9a-fA-F]+$")


def load_profile(path):
    if path.endswith(".gz"):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            return json.load(f)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def collect_unresolved_addresses(prof):
    """Walk every thread's funcTable; collect strings that are raw hex
    addresses (i.e., names that samply couldn't resolve)."""
    addrs = set()
    for t in prof.get("threads", []):
        strings = t.get("stringArray", [])
        name_col = t.get("funcTable", {}).get("name", [])
        for ni in name_col:
            if 0 <= ni < len(strings):
                s = strings[ni]
                if HEX_RE.match(s):
                    addrs.add(s)
    return addrs


def resolve_with_addr2line(addrs, binary, demangle=True):
    """Run addr2line + c++filt to map hex addresses to function names.
    Returns dict[hex_str -> resolved_name]. Unresolvable addresses map
    to themselves (so the table still has *something* to show).
    """
    if not addrs:
        return {}
    sorted_addrs = sorted(addrs)
    args = ["addr2line", "-e", binary, "-f"]
    if demangle:
        # addr2line -C uses libiberty demangling (handles C++, Rust v0,
        # legacy Rust _ZN..E since binutils 2.32). On binutils 2.38
        # (Ubuntu 22.04) this works for Rust v0 mangled symbols.
        args.append("-C")
    proc = subprocess.run(
        args,
        input="\n".join(sorted_addrs).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out = proc.stdout.decode("utf-8", errors="replace").splitlines()
    # addr2line emits TWO lines per address: function name, then file:line.
    mapping = {}
    for i, a in enumerate(sorted_addrs):
        fn = out[2 * i] if 2 * i < len(out) else "??"
        if fn == "??" or not fn.strip():
            mapping[a] = a  # keep the hex address as the "name"
        else:
            mapping[a] = fn.strip()
    return mapping


def short_name(name):
    """Strip Rust path::to::module:: prefixes and any trailing closure /
    hash suffix so the table reads cleanly.
    Examples:
        osprey_fdr::svm::train_one_fold::ha8b2c0d1
            -> svm::train_one_fold
        rayon_core::join::join_context::{{closure}}
            -> join::join_context::{{closure}}
    """
    if name.startswith("0x"):
        return name
    # Drop hash suffix at end (::h<hex>) which Rust emits for monomorphized
    # generics.
    name = re.sub(r"::h[0-9a-f]{14,}$", "", name)
    # Keep only the last 3 path segments for readability while still
    # giving enough context to recognize which crate the symbol came
    # from.
    parts = name.split("::")
    if len(parts) > 3:
        name = "::".join(parts[-3:])
    return name


def gather_thread(thread, address_map, own, total):
    samples = thread.get("samples") or {}
    stack_col = samples.get("stack") or []
    if not stack_col:
        return
    # Weight: prefer threadCPUDelta (microseconds of CPU) when present,
    # since that maps cleanly to dotTrace's CpuInstruction time. Fall
    # back to sample-count * meta.interval otherwise.
    cpu_col = samples.get("threadCPUDelta")

    stack_table = thread["stackTable"]
    prefix_col = stack_table["prefix"]
    frame_col = stack_table["frame"]
    frame_table = thread["frameTable"]
    func_col = frame_table["func"]
    func_table = thread["funcTable"]
    name_col = func_table["name"]
    strings = thread["stringArray"]

    def name_for_frame(stack_idx):
        if stack_idx is None or stack_idx < 0:
            return None
        frame_idx = frame_col[stack_idx]
        func_idx = func_col[frame_idx]
        ni = name_col[func_idx]
        if 0 <= ni < len(strings):
            raw = strings[ni]
            return address_map.get(raw, raw)
        return None

    for i, stack_idx in enumerate(stack_col):
        if stack_idx is None or stack_idx < 0:
            continue
        if cpu_col is not None and cpu_col[i] is not None:
            w = float(cpu_col[i]) / 1000.0  # microseconds -> milliseconds
        else:
            w = 1.0
        leaf = name_for_frame(stack_idx)
        if leaf:
            own[leaf] += w
        seen = set()
        cursor = stack_idx
        while cursor is not None and cursor >= 0:
            n = name_for_frame(cursor)
            if n and n not in seen:
                seen.add(n)
                total[n] += w
            cursor = prefix_col[cursor]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("profile")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--binary", help="ELF binary for addr2line resolution")
    ap.add_argument("--no-shorten", action="store_true",
                    help="Do not trim Rust path prefixes")
    args = ap.parse_args()

    prof = load_profile(args.profile)
    address_map = {}
    if args.binary:
        addrs = collect_unresolved_addresses(prof)
        sys.stderr.write(f"resolving {len(addrs)} addresses via addr2line "
                         f"on {args.binary}\n")
        address_map = resolve_with_addr2line(addrs, args.binary)

    own = defaultdict(float)
    total = defaultdict(float)
    for t in prof.get("threads", []):
        gather_thread(t, address_map, own, total)

    def emit(name):
        return name if args.no_shorten else short_name(name)

    rows = sorted(
        ((emit(n), own[n], total[n]) for n in total.keys()),
        key=lambda r: -r[1],
    )

    # Collapse rows with same shortened name (e.g., monomorphic generics)
    folded = defaultdict(lambda: [0.0, 0.0])
    for n, o, t in rows:
        folded[n][0] += o
        folded[n][1] += t
    rows = sorted(
        ((n, v[0], v[1]) for n, v in folded.items()),
        key=lambda r: -r[1],
    )

    import csv
    out = open(args.out, "w", newline="", encoding="utf-8") if args.out else sys.stdout
    w = csv.writer(out)
    w.writerow(["function", "own_ms", "total_ms"])
    for n, o, t in rows:
        w.writerow([n, f"{o:.1f}", f"{t:.1f}"])
    if args.out:
        out.close()
        sys.stderr.write(f"wrote {len(rows)} rows to {args.out}\n")


if __name__ == "__main__":
    main()
