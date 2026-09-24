#!/usr/bin/env python3
"""
Compare two sets of demultiplexed MS2 spectra, spectrum by spectrum.

Each input is an Osprey spectra cache: a plain `.spectra.bin` (for example one
Osprey built from an msconvert-demultiplexed mzML) or a `.demux.spectra.bin`
(Osprey's own demultiplexing of the raw file). Unlike Compare-SpectraCache.ps1,
which asks "byte identical?", this asks "how close?", because two
demultiplexers are not expected to agree to the bit.

Pairing: an MS2 record is identified by its retention time (the parent scan's,
which both tools copy) and its isolation-window center (the narrow bin). Within
one retention time the records are paired by nearest center, within
--center-tolerance Th. Peaks are paired by m/z within --mz-tolerance-ppm; both
tools keep the parent spectrum's centroid m/z values, so these should agree
exactly.

Per pair it reports the cosine similarity of the intensity vectors over the
union of peaks (a peak missing from one side counts as zero), the ratio of
total intensity, and the intensity carried by peaks only one side has. The
summary gives distributions, a breakdown by bin, and the worst pairs.

Cache layout (v4; see pwiz_tools/Osprey/Osprey.IO/SpectraCache.cs): magic
"OSPRSPC\\0" or "OSPRDMX\\0", u32 version, u64 source size, i64 source mtime,
u32 n_ms2, u32 n_ms1, [demux only: u32 length + UTF-8 descriptor], records,
MS1, index of n_ms2 x (i64 offset, f64 center, f64 lower, f64 upper, f64 rt),
footer (i64 ms1 offset, i64 index offset).

Example:
    python Compare-DemuxSpectra.py \
        --reference D:/test/osprey-runs/eclipse-staggered/msconvert/Ecl_..._10.spectra.bin \
        --test      D:/test/osprey-runs/eclipse-staggered/osprey/Ecl_..._10.demux.spectra.bin

Exit code 0 on a completed comparison (it reports, it does not judge), 2 on
unusable input.
"""

import argparse
import bisect
import struct
import sys
from collections import defaultdict

import numpy as np

PLAIN_MAGIC = b"OSPRSPC\x00"
DEMUX_MAGIC = b"OSPRDMX\x00"
INDEX_ENTRY = struct.Struct("<qdddd")
RECORD_HEAD = struct.Struct("<IdddddI")


class SpectraCache:
    """Random access to the MS2 records of one cache file."""

    def __init__(self, path):
        self.path = path
        self.file = open(path, "rb")
        head = self.file.read(36)
        if len(head) != 36 or head[:8] not in (PLAIN_MAGIC, DEMUX_MAGIC):
            raise ValueError(f"{path}: not an Osprey spectra cache")
        self.demux = head[:8] == DEMUX_MAGIC
        version, _, _, self.n_ms2, self.n_ms1 = struct.unpack("<IQqII", head[8:36])
        if version != 4:
            raise ValueError(f"{path}: cache format version {version}, expected 4")
        self.descriptor = None
        if self.demux:
            (length,) = struct.unpack("<I", self.file.read(4))
            self.descriptor = self.file.read(length).decode("utf-8")
        self.file.seek(-16, 2)
        _, index_offset = struct.unpack("<qq", self.file.read(16))
        self.file.seek(index_offset)
        raw = self.file.read(self.n_ms2 * INDEX_ENTRY.size)
        index = np.frombuffer(raw, dtype=np.dtype([("offset", "<i8"), ("center", "<f8"),
                                                    ("lower", "<f8"), ("upper", "<f8"),
                                                    ("rt", "<f8")]))
        self.index = index

    def read(self, offset):
        self.file.seek(offset)
        scan, rt, _, center, lower, upper, n = RECORD_HEAD.unpack(self.file.read(RECORD_HEAD.size))
        mzs = np.frombuffer(self.file.read(8 * n), dtype="<f8")
        intensities = np.frombuffer(self.file.read(4 * n), dtype="<f4").astype(np.float64)
        return scan, rt, center, lower + upper, mzs, intensities


def group_by_rt(index, rt_decimals):
    """rt key -> sorted list of (center, offset, width)."""
    groups = defaultdict(list)
    keys = np.round(index["rt"], rt_decimals)
    for key, center, offset, lower, upper in zip(keys, index["center"], index["offset"],
                                                 index["lower"], index["upper"]):
        groups[float(key)].append((float(center), int(offset), float(lower + upper)))
    for records in groups.values():
        records.sort()
    return groups


def pair_records(reference_groups, test_groups, center_tolerance):
    pairs = []
    unmatched_reference = 0
    unmatched_test = 0
    for key, reference_records in reference_groups.items():
        test_records = test_groups.get(key, [])
        test_centers = [r[0] for r in test_records]
        used = set()
        for center, offset, width in reference_records:
            i = bisect.bisect_left(test_centers, center)
            best = None
            for j in (i - 1, i):
                if 0 <= j < len(test_records) and j not in used:
                    d = abs(test_centers[j] - center)
                    if d <= center_tolerance and (best is None or d < best[0]):
                        best = (d, j)
            if best is None:
                unmatched_reference += 1
                continue
            used.add(best[1])
            pairs.append((key, center, width, offset, test_records[best[1]][1]))
        unmatched_test += len(test_records) - len(used)
    for key, test_records in test_groups.items():
        if key not in reference_groups:
            unmatched_test += len(test_records)
    pairs.sort(key=lambda p: p[3])
    return pairs, unmatched_reference, unmatched_test


def compare_peaks(ref_mz, ref_int, test_mz, test_int, ppm):
    """Returns (cosine, reference total, test total, reference-only total, test-only total).

    Each reference peak is matched to the nearest test peak within the tolerance. Centroids
    of one spectrum are far more than a ppm apart, so the match is one-to-one in practice.
    """
    ref_total = float(ref_int.sum())
    test_total = float(test_int.sum())
    ref_sq = float(np.dot(ref_int, ref_int))
    test_sq = float(np.dot(test_int, test_int))
    if len(ref_mz) == 0 or len(test_mz) == 0:
        cosine = 1.0 if ref_sq == 0 and test_sq == 0 else 0.0
        return cosine, ref_total, test_total, ref_total, test_total
    right = np.clip(np.searchsorted(test_mz, ref_mz), 0, len(test_mz) - 1)
    left = np.clip(right - 1, 0, len(test_mz) - 1)
    d_right = np.abs(test_mz[right] - ref_mz)
    d_left = np.abs(test_mz[left] - ref_mz)
    nearest = np.where(d_left < d_right, left, right)
    matched = np.minimum(d_left, d_right) <= ref_mz * ppm * 1e-6
    partner = nearest[matched]
    dot = float(np.dot(ref_int[matched], test_int[partner]))
    test_matched = np.zeros(len(test_mz), dtype=bool)
    test_matched[partner] = True
    ref_only = float(ref_int[~matched].sum())
    test_only = float(test_int[~test_matched].sum())
    cosine = dot / np.sqrt(ref_sq * test_sq) if ref_sq > 0 and test_sq > 0 else (
        1.0 if ref_sq == 0 and test_sq == 0 else 0.0)
    return cosine, ref_total, test_total, ref_only, test_only


def summed_parent(cache, records):
    """All records of one parent scan, summed by m/z (exact, since both keep parent centroids)."""
    mzs, intensities = [], []
    for _, offset, _ in records:
        _, _, _, _, mz, intensity = cache.read(offset)
        mzs.append(mz)
        intensities.append(intensity)
    if not mzs:
        return np.zeros(0), np.zeros(0)
    mz = np.concatenate(mzs)
    intensity = np.concatenate(intensities)
    unique, inverse = np.unique(mz, return_inverse=True)
    return unique, np.bincount(inverse, weights=intensity)


def compare_parents(reference, test, reference_groups, test_groups, args):
    cosines, ratios, exclusive = [], [], []
    keys = sorted(set(reference_groups) & set(test_groups))
    for n, key in enumerate(keys):
        if n % args.every != 0:
            continue
        ref_mz, ref_int = summed_parent(reference, reference_groups[key])
        test_mz, test_int = summed_parent(test, test_groups[key])
        cosine, ref_total, test_total, ref_only, test_only = compare_peaks(
            ref_mz, ref_int, test_mz, test_int, args.mz_tolerance_ppm)
        if ref_total == 0 and test_total == 0:
            continue
        cosines.append(cosine)
        if ref_total > 0:
            ratios.append(test_total / ref_total)
            exclusive.append((ref_only + test_only) / (ref_total + test_total))
    print(f"\nper parent scan ({len(cosines):,} parents; bins summed back to the parent):")
    print("  " + describe(cosines, "cosine"))
    if cosines:
        print(f"    fraction >= 0.9999: {np.mean(np.asarray(cosines) >= 0.9999):.3f}")
    print("  " + describe(ratios, "total intensity test/reference"))
    print("  " + describe(exclusive, "intensity in peaks only one side has"))


def describe(values, label):
    if len(values) == 0:
        return f"{label}: none"
    v = np.asarray(values)
    return (f"{label}: median {np.median(v):.4f}  p05 {np.percentile(v, 5):.4f}  "
            f"p25 {np.percentile(v, 25):.4f}  p75 {np.percentile(v, 75):.4f}  mean {v.mean():.4f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--reference", required=True, help="cache treated as expected (e.g. msconvert)")
    parser.add_argument("--test", required=True, help="cache under test (e.g. Osprey demux)")
    parser.add_argument("--rt-decimals", type=int, default=6,
                        help="decimals of RT (minutes) that identify a parent scan (default 6)")
    parser.add_argument("--center-tolerance", type=float, default=0.5,
                        help="max bin-center difference (Th) for a pair (default 0.5)")
    parser.add_argument("--mz-tolerance-ppm", type=float, default=1.0,
                        help="peak m/z match tolerance in ppm (default 1)")
    parser.add_argument("--every", type=int, default=1,
                        help="compare every Nth pair, for a quick look (default 1 = all)")
    parser.add_argument("--min-intensity", type=float, default=0.0,
                        help="ignore peaks below this intensity on both sides (default 0)")
    parser.add_argument("--worst", type=int, default=15, help="list this many worst pairs")
    parser.add_argument("--parents", action="store_true",
                        help="also compare per parent scan: all records at one retention time, "
                             "summed by m/z. Apportioned demux output sums back to the parent "
                             "spectrum, so a difference here means the INPUT centroids differ, "
                             "not the allocation between bins")
    args = parser.parse_args()

    try:
        reference = SpectraCache(args.reference)
        test = SpectraCache(args.test)
    except (OSError, ValueError) as ex:
        print(f"ERROR: {ex}", file=sys.stderr)
        return 2

    print(f"reference: {args.reference}\n  {reference.n_ms2:,} MS2"
          + (f"; demux descriptor {reference.descriptor}" if reference.demux else ""))
    print(f"test:      {args.test}\n  {test.n_ms2:,} MS2"
          + (f"; demux descriptor {test.descriptor}" if test.demux else ""))

    reference_groups = group_by_rt(reference.index, args.rt_decimals)
    test_groups = group_by_rt(test.index, args.rt_decimals)
    pairs, unmatched_reference, unmatched_test = pair_records(
        reference_groups, test_groups, args.center_tolerance)
    print(f"paired {len(pairs):,}; reference-only {unmatched_reference:,}; test-only {unmatched_test:,}")
    if args.parents:
        compare_parents(reference, test, reference_groups, test_groups, args)

    cosines, ratios, ref_only_fracs, test_only_fracs = [], [], [], []
    by_bin = defaultdict(list)
    worst = []
    totals = np.zeros(4)
    for n, (rt, center, width, ref_offset, test_offset) in enumerate(pairs):
        if n % args.every != 0:
            continue
        _, _, _, _, ref_mz, ref_int = reference.read(ref_offset)
        _, _, _, _, test_mz, test_int = test.read(test_offset)
        if args.min_intensity > 0:
            keep = ref_int >= args.min_intensity
            ref_mz, ref_int = ref_mz[keep], ref_int[keep]
            keep = test_int >= args.min_intensity
            test_mz, test_int = test_mz[keep], test_int[keep]
        cosine, ref_total, test_total, ref_only, test_only = compare_peaks(
            ref_mz, ref_int, test_mz, test_int, args.mz_tolerance_ppm)
        totals += (ref_total, test_total, ref_only, test_only)
        if ref_total == 0 and test_total == 0:
            continue
        cosines.append(cosine)
        if ref_total > 0:
            ratios.append(test_total / ref_total)
            ref_only_fracs.append(ref_only / ref_total)
        if test_total > 0:
            test_only_fracs.append(test_only / test_total)
        by_bin[round(center)].append(cosine)
        worst.append((cosine, rt, center, ref_total, test_total, len(ref_mz), len(test_mz)))

    print()
    print(describe(cosines, "cosine (union of peaks)"))
    if cosines:
        c = np.asarray(cosines)
        print(f"  fraction >= 0.99: {np.mean(c >= 0.99):.3f}   >= 0.95: {np.mean(c >= 0.95):.3f}   "
              f"< 0.80: {np.mean(c < 0.80):.3f}")
    print(describe(ratios, "total intensity test/reference"))
    print(describe(ref_only_fracs, "reference intensity in reference-only peaks"))
    print(describe(test_only_fracs, "test intensity in test-only peaks"))
    if totals[0] > 0:
        print(f"overall: test/reference intensity {totals[1] / totals[0]:.4f}; "
              f"reference-only {totals[2] / totals[0]:.4f}; test-only {totals[3] / max(totals[1], 1e-300):.4f}")

    print("\nby bin center (Th): pairs, median cosine, p05 cosine")
    for key in sorted(by_bin):
        v = np.asarray(by_bin[key])
        print(f"  {key:7.0f}  {len(v):8d}  {np.median(v):.4f}  {np.percentile(v, 5):.4f}")

    if args.worst > 0 and worst:
        worst.sort()
        print(f"\nworst {args.worst} pairs: cosine, rt (min), center, reference total, test total, "
              f"reference peaks, test peaks")
        for row in worst[:args.worst]:
            print(f"  {row[0]:.4f}  {row[1]:9.4f}  {row[2]:9.3f}  {row[3]:12.4g}  {row[4]:12.4g}  "
                  f"{row[5]:5d}  {row[6]:5d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
