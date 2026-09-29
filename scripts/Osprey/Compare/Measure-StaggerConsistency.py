#!/usr/bin/env python3
"""
Library-free accuracy proxy for staggered-DIA demultiplexing: stagger consistency.

In a k=2 stagger every narrow bin is sampled alternately through its two parent
windows (A, B, A, B, ...), each of which also carries a DIFFERENT neighboring
bin. A demultiplexer that splits intensity between bins correctly gives each
fragment chromatogram in a bin a smooth shape across that alternation. One that
splits it with a bias gives the A-derived and B-derived points different
levels, so the chromatogram zig-zags. Because consecutive points of a bin always
come from different parents, the deviation of each point from the time-weighted
average of its two neighbors measures that disagreement (plus the peak's own
curvature and counting noise, which are the same for every demultiplexer given
the same input).

Chromatographic events are found once, in the REFERENCE output: per bin, the
reference peaks are clustered into fragment channels by m/z, each channel's
chromatogram is built on the bin's own acquisition times, and the most intense
apexes are kept. Every input is then measured on exactly those events (same bin,
same m/z range, same apex window), so the tools are compared on identical
chromatography.

Per event: zigzag = sum |x_i - interp(x_{i-1}, x_{i+1}; t_i)| / sum x_i over the
apex window. Lower is more self-consistent.

Inputs are Osprey spectra caches (see Compare-DemuxSpectra.py): a plain
.spectra.bin of an msconvert-demultiplexed mzML, or a .demux.spectra.bin.

Example:
    python Measure-StaggerConsistency.py \
        --reference msconvert=D:/.../msconvert/RUN.spectra.bin \
        --input osprey=D:/.../osprey-default/RUN.demux.spectra.bin \
        --input osprey-msconvert-like=D:/.../osprey-pwizlike/RUN.demux.spectra.bin
"""

import argparse
import importlib.util
import os
import sys
from collections import defaultdict

import numpy as np

# The cache reader lives in the sibling comparator, whose file name is not importable.
_spec = importlib.util.spec_from_file_location(
    "compare_demux_spectra",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "Compare-DemuxSpectra.py"))
_compare = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_compare)
SpectraCache = _compare.SpectraCache


def named(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, path = value.split("=", 1)
    return name, path


def bins_of(cache, rt_decimals):
    """bin key (center to 0.1 Th) -> list of (rt key, offset) sorted by rt."""
    bins = defaultdict(list)
    for offset, center, rt in zip(cache.index["offset"], cache.index["center"], cache.index["rt"]):
        bins[int(round(center * 10))].append((round(float(rt), rt_decimals), int(offset)))
    for records in bins.values():
        records.sort()
    return bins


def match_bin(key, candidates):
    """The candidate bin key nearest to `key`, within 1 Th."""
    best = min(candidates, key=lambda c: abs(c - key), default=None)
    return best if best is not None and abs(best - key) <= 10 else None


def read_bin(cache, records):
    return [cache.read(offset)[4:] for _, offset in records]


def channel_matrix(spectra, low, high):
    """records x channels: summed intensity of each record's peaks inside each [low, high]."""
    out = np.zeros((len(spectra), len(low)))
    for r, (mz, intensity) in enumerate(spectra):
        if len(mz) == 0:
            continue
        cumulative = np.concatenate(([0.0], np.cumsum(intensity)))
        lo = np.searchsorted(mz, low, side="left")
        hi = np.searchsorted(mz, high, side="right")
        out[r] = cumulative[hi] - cumulative[lo]
    return out


def find_channels(spectra, ppm, max_width_ppm, max_channels):
    """
    Single-linkage m/z clusters over all peaks of a bin, as [low, high] ranges: the
    `max_channels` most intense, leaving out any wider than `max_width_ppm` (a cluster that
    chained through a dense region is several fragments, not one channel).
    """
    parts = [(mz, intensity) for mz, intensity in spectra if len(mz)]
    if not parts:
        return np.zeros(0), np.zeros(0)
    all_mz = np.concatenate([mz for mz, _ in parts])
    all_int = np.concatenate([intensity for _, intensity in parts])
    order = np.argsort(all_mz, kind="stable")
    all_mz, all_int = all_mz[order], all_int[order]
    gaps = np.diff(all_mz) > all_mz[:-1] * ppm * 1e-6
    starts = np.concatenate(([0], np.nonzero(gaps)[0] + 1))
    ends = np.concatenate((np.nonzero(gaps)[0], [len(all_mz) - 1]))
    low, high = all_mz[starts], all_mz[ends]
    totals = np.add.reduceat(all_int, starts)
    keep = (high - low) <= low * max_width_ppm * 1e-6
    low, high, totals = low[keep], high[keep], totals[keep]
    top = np.sort(np.argsort(-totals, kind="stable")[:max_channels])
    return low[top], high[top]


def zigzag(x, t):
    """sum |x_i - time-weighted mean of neighbors| / sum x over interior points."""
    left, mid, right = x[:-2], x[1:-1], x[2:]
    tl, tm, tr = t[:-2], t[1:-1], t[2:]
    span = tr - tl
    predicted = np.where(span > 0, (left * (tr - tm) + right * (tm - tl)) / np.where(span > 0, span, 1), mid)
    total = mid.sum()
    return np.abs(mid - predicted).sum() / total if total > 0 else np.nan


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--reference", type=named, required=True,
                        help="NAME=cache whose output defines the chromatographic events")
    parser.add_argument("--input", type=named, action="append", default=[],
                        help="NAME=cache to measure (repeatable); the reference is always measured")
    parser.add_argument("--rt-decimals", type=int, default=6)
    parser.add_argument("--channel-ppm", type=float, default=5.0,
                        help="m/z gap that separates fragment channels (default 5 ppm)")
    parser.add_argument("--max-channel-width-ppm", type=float, default=20.0,
                        help="channels wider than this are chained clusters and are dropped (default 20)")
    parser.add_argument("--channels-per-bin", type=int, default=2000,
                        help="most intense channels per bin considered for events (default 2000)")
    parser.add_argument("--half-window", type=int, default=6,
                        help="samples on each side of the apex (default 6: 3 per parent window)")
    parser.add_argument("--events-per-bin", type=int, default=300,
                        help="most intense apexes kept per bin (default 300)")
    parser.add_argument("--min-points", type=int, default=7,
                        help="nonzero reference points required in the apex window (default 7)")
    parser.add_argument("--bins-every", type=int, default=1,
                        help="measure every Nth bin, for a quick look (default 1 = all)")
    args = parser.parse_args()

    names = [args.reference[0]] + [name for name, _ in args.input]
    caches = [SpectraCache(args.reference[1])] + [SpectraCache(path) for _, path in args.input]
    bin_maps = [bins_of(cache, args.rt_decimals) for cache in caches]

    scores = defaultdict(list)          # name -> per-event zigzag
    by_region = defaultdict(lambda: defaultdict(list))
    reference_bins = sorted(bin_maps[0])
    for n, key in enumerate(reference_bins):
        if n % args.bins_every != 0:
            continue
        ref_records = bin_maps[0][key]
        times = np.array([rt for rt, _ in ref_records])
        ref_spectra = read_bin(caches[0], ref_records)
        low, high = find_channels(ref_spectra, args.channel_ppm, args.max_channel_width_ppm,
                                  args.channels_per_bin)
        if len(low) == 0:
            continue
        low = low * (1 - 2e-6)
        high = high * (1 + 2e-6)
        ref_xic = channel_matrix(ref_spectra, low, high)

        # Events: each channel's apex, with a full window and enough signal around it.
        h = args.half_window
        apex = ref_xic.argmax(axis=0)
        peak = ref_xic.max(axis=0)
        valid = (apex >= h) & (apex < len(times) - h)
        events = []
        for c in np.nonzero(valid)[0]:
            window = ref_xic[apex[c] - h:apex[c] + h + 1, c]
            if np.count_nonzero(window) >= args.min_points:
                events.append((peak[c], c))
        events.sort(reverse=True)
        events = events[:args.events_per_bin]
        if not events:
            continue

        for name, cache, bin_map in zip(names, caches, bin_maps):
            other = match_bin(key, bin_map)
            if other is None:
                continue
            records = bin_map[other]
            record_times = np.array([rt for rt, _ in records])
            if len(records) != len(ref_records) or not np.allclose(record_times, times, atol=1e-5):
                print(f"WARNING: {name}: bin {key / 10:.1f} has different acquisition times; skipped",
                      file=sys.stderr)
                continue
            xic = ref_xic if name == names[0] else channel_matrix(read_bin(cache, records), low, high)
            for _, c in events:
                a = apex[c]
                z = zigzag(xic[a - h:a + h + 1, c], times[a - h:a + h + 1])
                if not np.isnan(z):
                    scores[name].append((key, c, z))
                    by_region[name][int(key / 10 // 100 * 100)].append(z)

    # Pair events across inputs so every comparison is on identical chromatography.
    keyed = {name: {(k, c): z for k, c, z in values} for name, values in scores.items()}
    common = set.intersection(*(set(v) for v in keyed.values())) if keyed else set()
    print(f"events measured in every input: {len(common):,} "
          f"(bins every {args.bins_every}, top {args.events_per_bin} apexes per bin)")
    print("\nzigzag (lower = the two parent windows agree better)")
    print(f"  {'input':28s} {'median':>8s} {'mean':>8s} {'p90':>8s}   {'lower than ' + names[0]:>20s}")
    ref_values = np.array([keyed[names[0]][e] for e in sorted(common)])
    for name in names:
        values = np.array([keyed[name][e] for e in sorted(common)])
        if len(values) == 0:
            continue
        better = np.mean(values < ref_values - 1e-12) if name != names[0] else float("nan")
        print(f"  {name:28s} {np.median(values):8.4f} {values.mean():8.4f} "
              f"{np.percentile(values, 90):8.4f}   {better:20.3f}")

    print("\nmedian zigzag by precursor m/z region")
    regions = sorted({r for name in names for r in by_region[name]})
    print("  " + "region".rjust(8) + "".join(f"{name[:18]:>20s}" for name in names))
    for region in regions:
        row = "".join(f"{np.median(by_region[name][region]):20.4f}" if by_region[name][region] else
                      f"{'-':>20s}" for name in names)
        print(f"  {region:8d}{row}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
