#!/usr/bin/env python3
"""Simulate Osprey's gendecoy path over a real target set and count I/L collisions.

Osprey generates decoys itself when the library does not supply them: reverse preserving the
C-terminus, falling back to cycling the internal residues 1..min(len,10), accepting the first
candidate that differs from its target, collides with no target EXACTLY, and passes the
fragment-overlap gate.

The question this answers: does the overlap gate incidentally catch decoys that are I/L-isobaric
to some OTHER target? It should not - the gate compares a candidate to its own source while a
collision is a match to a different target - but that is worth measuring rather than asserting.

Usage: python osprey_gendecoy_il.py <osprey_library_db_pairing.tsv>
"""
import bisect
import sys
from collections import defaultdict

MAX_FRAGMENT_OVERLAP = 0.4
LADDER_MATCH_TOLERANCE = 0.02
MONO = {'G': 57.02146, 'A': 71.03711, 'S': 87.03203, 'P': 97.05276, 'V': 99.06841,
        'T': 101.04768, 'C': 103.00919, 'L': 113.08406, 'I': 113.08406, 'N': 114.04293,
        'D': 115.02694, 'Q': 128.05858, 'K': 128.09496, 'E': 129.04259, 'M': 131.04049,
        'H': 137.05891, 'F': 147.06841, 'R': 156.10111, 'Y': 163.06333, 'W': 186.07931}
H2O, PROTON = 18.01056, 1.007276


def ladder(seq):
    n = len(seq)
    if n < 2:
        return []
    out, prefix, ok = [], 0.0, True
    prefixes = []
    for ch in seq:
        m = MONO.get(ch)
        if m is None:
            ok = False
        prefix = prefix + m if (ok and m is not None) else float('nan')
        prefixes.append(prefix)
    suffix, ok = 0.0, True
    suffixes = []
    for ch in reversed(seq):
        m = MONO.get(ch)
        if m is None:
            ok = False
        suffix = suffix + m if (ok and m is not None) else float('nan')
        suffixes.append(suffix)
    for o in range(1, n):
        b = prefixes[o - 1]
        if b == b:
            out.append(b + PROTON)
        y = suffixes[o - 1]
        if y == y:
            out.append(y + H2O + PROTON)
    return out


def acceptable(target, cand):
    c = ladder(cand)
    if not c:
        return True
    t = sorted(ladder(target))
    if not t:
        return True
    hits = 0
    for mz in c:
        i = bisect.bisect_left(t, mz)
        if i < len(t) and t[i] - mz <= LADDER_MATCH_TOLERANCE:
            hits += 1
        elif i > 0 and mz - t[i - 1] <= LADDER_MATCH_TOLERANCE:
            hits += 1
    return hits / len(c) <= MAX_FRAGMENT_OVERLAP


def rev_cterm(s):
    return s if len(s) <= 2 else s[-2::-1] + s[-1]


def cycle_cterm(s, c):
    if len(s) <= 2 or c == 0:
        return s
    mid = s[:-1]
    c %= len(mid)
    return mid[c:] + mid[:c] + s[-1]


groups = defaultdict(dict)
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    f.readline()
    for ln in f:
        p = ln.rstrip('\n').split('\t')
        if len(p) >= 5:
            groups[p[4]][p[3]] = p[0]

targets = sorted({g['target'] for g in groups.values() if g.get('target')})
tset = set(targets)
tset_il = {t.replace('I', 'L') for t in targets}
print(f"targets: {len(targets):,}", flush=True)

generated = excluded = il_collide = exact_collide = 0
examples = []
for t in targets:
    chosen = None
    rev = rev_cterm(t)
    if rev != t and rev not in tset and acceptable(t, rev):
        chosen = rev
    else:
        for c in range(1, min(len(t), 10) + 1):
            cyc = cycle_cterm(t, c)
            if cyc != t and cyc not in tset and acceptable(t, cyc):
                chosen = cyc
                break
    if chosen is None:
        excluded += 1
        continue
    generated += 1
    if chosen in tset:
        exact_collide += 1          # cannot happen; the loop rejects it
    elif chosen.replace('I', 'L') in tset_il:
        il_collide += 1
        if len(examples) < 8:
            examples.append((t, chosen))

print(f"\nOsprey gendecoy simulation (reverse -> cycle, overlap gate ON)")
print(f"  decoys generated : {generated:,}")
print(f"  excluded         : {excluded:,}")
print(f"  EXACT collisions with a target      : {exact_collide:,}")
print(f"  I/L-ISOBARIC collisions with a target: {il_collide:,}"
      f"  ({100.0 * il_collide / max(1, generated):.4f}%)")
if examples:
    print("\n  examples - decoy is mass-identical to a DIFFERENT target, same ladder:")
    for src, d in examples:
        print(f"    from {src:<24} -> {d:<24} (normalises to {d.replace('I','L')})")
