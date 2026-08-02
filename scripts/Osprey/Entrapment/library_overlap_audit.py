#!/usr/bin/env python3
"""Audit a pairing manifest for entrapment (and decoy) near-copies of their own targets.

Complements pass1_entrap.py / pass1_compare.py, which characterise the ACCEPTED set of a
search run. This one needs no run: it reads the library's own pairing manifest and reports
the fragment-overlap distribution across every target/entrapment and target/decoy pair, which
is what the Carafe similarity gate acts on.

Use it to confirm a rebuilt library actually cleared the contamination before spending a
multi-hour search on it. The library-wide rejectable fraction is the honest denominator; the
accepted-set fraction is ~6.5x higher because near-copies are enriched among hits, and only a
real run can measure that.

Usage:
  python library_overlap_audit.py <osprey_library_db_pairing.tsv> [--label NAME] [--sample N]
"""
import argparse
import bisect
from collections import defaultdict

# Osprey DecoyGenerator constants - keep in step with DecoySimilarityGate.java.
MAX_FRAGMENT_OVERLAP = 0.4
LADDER_MATCH_TOLERANCE = 0.02

MONO = {'G': 57.02146, 'A': 71.03711, 'S': 87.03203, 'P': 97.05276, 'V': 99.06841,
        'T': 101.04768, 'C': 103.00919, 'L': 113.08406, 'I': 113.08406, 'N': 114.04293,
        'D': 115.02694, 'Q': 128.05858, 'K': 128.09496, 'E': 129.04259, 'M': 131.04049,
        'H': 137.05891, 'F': 147.06841, 'R': 156.10111, 'Y': 163.06333, 'W': 186.07931}
H2O = 18.01056
PROTON = 1.007276


def ladder(seq):
    """Singly-charged b and y ions for every cleavage site; ions spanning an unknown residue
    are skipped rather than aborting the ladder."""
    n = len(seq)
    if n < 2:
        return []
    out = []
    prefix = 0.0
    ok_prefix = True
    prefixes = []
    for ch in seq:
        m = MONO.get(ch)
        if m is None:
            ok_prefix = False
        prefix = prefix + m if (ok_prefix and m is not None) else float('nan')
        prefixes.append(prefix)
    suffix = 0.0
    ok_suffix = True
    suffixes = []
    for ch in reversed(seq):
        m = MONO.get(ch)
        if m is None:
            ok_suffix = False
        suffix = suffix + m if (ok_suffix and m is not None) else float('nan')
        suffixes.append(suffix)
    for ordinal in range(1, n):
        b = prefixes[ordinal - 1]
        if b == b:
            out.append(b + PROTON)
        y = suffixes[ordinal - 1]
        if y == y:
            out.append(y + H2O + PROTON)
    return out


def overlap(target, candidate):
    """Fraction of the candidate's ladder within tolerance of the target's."""
    cand = ladder(candidate)
    if not cand:
        return 0.0
    tgt = sorted(ladder(target))
    if not tgt:
        return 0.0
    matches = 0
    for mz in cand:
        i = bisect.bisect_left(tgt, mz)
        if i < len(tgt) and tgt[i] - mz <= LADDER_MATCH_TOLERANCE:
            matches += 1
        elif i > 0 and mz - tgt[i - 1] <= LADDER_MATCH_TOLERANCE:
            matches += 1
    return matches / len(cand)


def il_normalize(seq):
    """I->L normalised form.

    I and L are isobaric (113.08406), so two sequences differing only by I<->L are
    mass-identical AND produce identical b/y ladders - MS cannot separate them. An entrapment
    peptide I/L-identical to ANY real target is detected wherever that target is, so every one
    of those detections is counted false when it is not.

    This is invisible to both of the other checks here. Exact string comparison says the
    sequences differ, and the overlap gate compares a candidate to its OWN paired target while
    a collision is a match to a DIFFERENT one.
    """
    return seq.replace('I', 'L')


def identity(a, b):
    """Positional identity, reported for context only - it is NOT gated on. It is a weakly
    correlated proxy that both misses real harm and flags harmless cases."""
    if not a or not b:
        return 0.0
    n = min(len(a), len(b))
    return sum(1 for i in range(n) if a[i] == b[i]) / max(len(a), len(b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('manifest')
    ap.add_argument('--label', default='')
    ap.add_argument('--sample', type=int, default=0,
                    help='audit only the first N quartets (0 = all)')
    a = ap.parse_args()

    groups = defaultdict(dict)
    with open(a.manifest, 'r', encoding='utf-8') as f:
        f.readline()
        for ln in f:
            p = ln.rstrip('\n').split('\t')
            if len(p) >= 5:
                groups[p[4]][p[3]] = p[0]

    keys = sorted(groups, key=int)
    if a.sample:
        keys = keys[:a.sample]

    # Collision indexes over the FULL target set, not the audited sample - a collision is a match
    # to any target anywhere, so sampling the index would under-report it.
    all_targets = set()
    for g in groups.values():
        t = g.get('target')
        if t:
            all_targets.add(t)
    targets_il = {il_normalize(t) for t in all_targets}

    ent_over, dec_over, pdec_over, ent_ident = [], [], [], []
    ent_rejectable, dec_rejectable, pdec_rejectable = 0, 0, 0
    ent_exact_collide, ent_il_collide = 0, 0
    dec_exact_collide, dec_il_collide = 0, 0
    il_examples = []
    worst = []
    for k in keys:
        g = groups[k]
        t = g.get('target')
        if not t:
            continue
        for seq, kind in ((g.get('p_target'), 'ent'), (g.get('decoy'), 'dec')):
            if not seq:
                continue
            if seq in all_targets:
                if kind == 'ent':
                    ent_exact_collide += 1
                else:
                    dec_exact_collide += 1
            elif il_normalize(seq) in targets_il:
                if kind == 'ent':
                    ent_il_collide += 1
                    if len(il_examples) < 6:
                        il_examples.append((t, seq))
                else:
                    dec_il_collide += 1
        pt = g.get('p_target')
        if pt:
            o = overlap(t, pt)
            ent_over.append(o)
            ent_ident.append(identity(t, pt))
            if o > MAX_FRAGMENT_OVERLAP:
                ent_rejectable += 1
                if len(worst) < 10:
                    worst.append((o, t, pt))
        d = g.get('decoy')
        if d:
            o = overlap(t, d)
            dec_over.append(o)
            if o > MAX_FRAGMENT_OVERLAP:
                dec_rejectable += 1
        # The entrapment population's own decoy, measured against the entrapment it was derived
        # from - not against the target. Entrapment competes against p_decoy exactly as targets
        # compete against decoy, so leaving this relationship unmeasured would hide the same
        # asymmetry one level down.
        pd = g.get('p_decoy')
        if pt and pd:
            o = overlap(pt, pd)
            pdec_over.append(o)
            if o > MAX_FRAGMENT_OVERLAP:
                pdec_rejectable += 1

    def summarize(name, vals, rejectable):
        if not vals:
            print(f"{name}: none present")
            return
        s = sorted(vals)
        n = len(s)
        print(f"\n{name}  (n = {n:,})")
        print(f"  median overlap      : {s[n // 2]:.4f}")
        print(f"  90th / 99th         : {s[int(0.90 * n)]:.4f} / {s[int(0.99 * n)]:.4f}")
        print(f"  max                 : {s[-1]:.4f}")
        print(f"  REJECTABLE (>{MAX_FRAGMENT_OVERLAP}) : {rejectable:,}  ({100.0 * rejectable / n:.4f}%)")

    print(f"=== library overlap audit {('- ' + a.label) if a.label else ''} ===")
    print(f"manifest: {a.manifest}")
    print(f"quartets audited: {len(keys):,}")
    summarize('target vs entrapment (p_target)', ent_over, ent_rejectable)
    summarize('target vs decoy', dec_over, dec_rejectable)
    summarize('entrapment vs its decoy (p_decoy)', pdec_over, pdec_rejectable)
    if ent_ident:
        si = sorted(ent_ident)
        print(f"\nentrapment positional identity (context only, not gated)")
        print(f"  median / 99th       : {si[len(si) // 2]:.4f} / {si[int(0.99 * len(si))]:.4f}")
    if worst:
        print("\nworst surviving entrapment overlaps:")
        for o, t, pt in sorted(worst, reverse=True):
            print(f"  {o:.4f}  {t} -> {pt}")

    print("\nindistinguishable-from-a-target collisions (any target, not just the paired one)")
    print(f"  entrapment: {ent_exact_collide:,} exact, {ent_il_collide:,} I/L-isobaric")
    print(f"  decoy     : {dec_exact_collide:,} exact, {dec_il_collide:,} I/L-isobaric")
    if il_examples:
        print("  examples (target -> entrapment, mass-identical with the same ladder):")
        for t, pt in il_examples:
            print(f"    {t} -> {pt}")
    if ent_exact_collide == 0 and ent_il_collide > 0:
        print("  NOTE: an exact-string audit would report this library CLEAN. It is not.")


if __name__ == '__main__':
    main()
