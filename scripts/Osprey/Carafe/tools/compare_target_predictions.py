#!/usr/bin/env python3
"""Compare the TARGET side of two Carafe libraries.

Targets are untouched by the similarity gate and by the entrapment source, so any
target-side difference between two libraries is the PREDICTION run, not the variable under
test. If two libraries are to serve as a controlled comparison, their target precursors must
report the same fragment sets.

Samples by hashing the stripped sequence, so the two files are matched without assuming
anything about row order. One streaming pass per file.

Usage:
  python compare_target_predictions.py <libA.tsv> <libB.tsv> [--modulus 500]
"""
import argparse
import sys
import zlib
from collections import defaultdict


def load(path, modulus):
    """precursor -> list of (fragment_mz, relative_intensity), for sampled TARGET rows."""
    frags = defaultdict(list)
    rt = {}
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        header = f.readline().rstrip('\n').split('\t')
        col = {name: i for i, name in enumerate(header)}
        i_mod = col['ModifiedPeptide']; i_strip = col['StrippedPeptide']
        i_z = col['PrecursorCharge']; i_prot = col['ProteinID']
        i_rt = col['Tr_recalibrated']
        i_fmz = col['FragmentMz']; i_int = col['RelativeIntensity']
        n = 0
        for line in f:
            n += 1
            p = line.rstrip('\n').split('\t')
            if len(p) <= i_int:
                continue
            prot = p[i_prot]
            # Targets only: not a decoy, not an entrapment shadow.
            if prot.startswith('decoy_') or '_p_target' in prot:
                continue
            strip = p[i_strip]
            if zlib.crc32(strip.encode()) % modulus:
                continue
            key = (p[i_mod], p[i_z])
            frags[key].append((p[i_fmz], p[i_int]))
            rt[key] = p[i_rt]
    print(f"  {path.split(chr(92))[-1]}: {n:,} rows scanned, {len(frags):,} sampled target precursors",
          file=sys.stderr)
    return frags, rt


ap = argparse.ArgumentParser()
ap.add_argument('libA')
ap.add_argument('libB')
ap.add_argument('--modulus', type=int, default=500)
a = ap.parse_args()

print('loading (one streaming pass each)...', file=sys.stderr)
fa, rta = load(a.libA, a.modulus)
fb, rtb = load(a.libB, a.modulus)

shared = set(fa) & set(fb)
print(f"\nshared target precursors: {len(shared):,}")
if not shared:
    sys.exit('no shared precursors - check the inputs')

identical_sets = 0
identical_full = 0
int_diffs = []
rt_diffs = []
for k in shared:
    mzA = [x[0] for x in fa[k]]
    mzB = [x[0] for x in fb[k]]
    if mzA == mzB:
        identical_sets += 1
        if fa[k] == fb[k]:
            identical_full += 1
        for (m1, i1), (m2, i2) in zip(fa[k], fb[k]):
            try:
                v1, v2 = float(i1), float(i2)
            except ValueError:
                continue
            if max(v1, v2) >= 0.05:
                int_diffs.append(abs(v1 - v2) / max(v1, v2) * 100.0)
    try:
        rt_diffs.append(abs(float(rta[k]) - float(rtb[k])))
    except (ValueError, KeyError):
        pass

n = len(shared)
print(f"fragment m/z lists identical      : {identical_sets:,} / {n:,}  ({100.0*identical_sets/n:.1f}%)")
print(f"fragment m/z AND intensity identical: {identical_full:,} / {n:,}  ({100.0*identical_full/n:.1f}%)")


def pct(vals, p):
    if not vals:
        return float('nan')
    s = sorted(vals)
    return s[min(len(s) - 1, int(p * len(s)))]


if int_diffs:
    print(f"\nrelative intensity difference (fragments >=5% intensity, n={len(int_diffs):,})")
    print(f"  median {pct(int_diffs,0.50):.3f}%   p90 {pct(int_diffs,0.90):.3f}%   "
          f"p99 {pct(int_diffs,0.99):.3f}%   max {max(int_diffs):.3f}%")
else:
    print("\nrelative intensity difference: none measurable")
if rt_diffs:
    print(f"\nTr_recalibrated difference (n={len(rt_diffs):,})")
    print(f"  median {pct(rt_diffs,0.50):.4f} min   p90 {pct(rt_diffs,0.90):.4f}   "
          f"p99 {pct(rt_diffs,0.99):.4f}   max {max(rt_diffs):.4f}")
