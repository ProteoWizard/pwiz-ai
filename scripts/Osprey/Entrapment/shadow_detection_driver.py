#!/usr/bin/env python3
"""Is a CROSS-group shadow's detection actually driven by the target it shadows?

This is the measurement that separates the two readings of short-peptide shadowing, and it needs
no new library and no new search - only a pairing manifest and an accepted set already produced by
pass1_entrap.py.

  * If an accepted shadow entrapment's shadowed TARGET is accepted at the background rate, its
    detection is not shadowing-driven. Gating it removes a valid false-discovery model, i.e. bias.
  * If the shadowed target is accepted well ABOVE background, the detection IS shadowing-driven -
    the entrapment is riding a real peptide's signal - and gating it is a correction.

Bucketed by peptide length, because that is where the decision sits: gating everything and gating
only length >= 9 differ by ~3.4x in the headline FDP number.

THE CONTROL IS MASS-MATCHED, which is what makes this an odds ratio rather than an anecdote. For
every accepted entrapment, its isobaric window is split into targets it shadows (ladder overlap >
0.70) and targets it does not. Both halves sit in the SAME precursor-mass window, drawn from the
same proteome, so they share abundance and detectability priors; they differ only in fragment
overlap. Comparing the accepted rate of the two halves isolates the one variable.

This is the same design as this file series' original 34.9x result (near-copies whose SOURCE
target was also accepted, 54.0% against 1.6% for dissimilar entrapment), moved from the pairwise
relationship to the set-wise one.

Usage:
  python shadow_detection_driver.py <pairing.tsv> <arm.json> [--overlap 0.70] [--mass-tol 0.01]

<arm.json> is the output of pass1_entrap.py: {"info": {entry_id: [sequence, protein_ids, q]}}.

Validated on a synthetic accepted set drawn by row position from a pre-gate manifest, where an
entrapment's acceptance is by construction unrelated to its shadowed target's: it returns an odds
ratio of 1.0 at every length. The null case reads as null, which is the property that makes a
non-null reading worth believing.
"""
import argparse
import bisect
import json
import re

LADDER_MATCH_TOLERANCE = 0.02

MONO = {'G': 57.02146, 'A': 71.03711, 'S': 87.03203, 'P': 97.05276, 'V': 99.06841,
        'T': 101.04768, 'C': 103.00919, 'L': 113.08406, 'I': 113.08406, 'N': 114.04293,
        'D': 115.02694, 'Q': 128.05858, 'K': 128.09496, 'E': 129.04259, 'M': 131.04049,
        'H': 137.05891, 'F': 147.06841, 'R': 156.10111, 'Y': 163.06333, 'W': 186.07931}
H2O = 18.01056
PROTON = 1.007276

MOD = re.compile(r'\[[^\]]*\]')


def strip_sequence(seq):
    """Bare residue string. Osprey reports modifications inline (C[+57.0215]), and the manifest
    carries stripped sequences, so both sides have to be reduced to the same form before any
    comparison."""
    return ''.join(ch for ch in MOD.sub('', seq or '') if 'A' <= ch <= 'Z')


def neutral_mass(seq):
    total = H2O
    for ch in seq:
        m = MONO.get(ch)
        if m is None:
            return None
        total += m
    return total


def ladder(seq):
    n = len(seq)
    if n < 2:
        return []
    prefixes, suffixes, acc = [], [], 0.0
    for ch in seq:
        acc += MONO.get(ch, float('nan'))
        prefixes.append(acc)
    acc = 0.0
    for ch in reversed(seq):
        acc += MONO.get(ch, float('nan'))
        suffixes.append(acc)
    out = []
    for ordinal in range(1, n):
        b = prefixes[ordinal - 1]
        if b == b:
            out.append(b + PROTON)
        y = suffixes[ordinal - 1]
        if y == y:
            out.append(y + H2O + PROTON)
    return out


def overlap(target, candidate):
    """Fraction of the candidate's ladder within tolerance of the target's - the same statistic
    library_overlap_audit.py and Carafe's DecoySimilarityGate compute."""
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


def read_manifest(path):
    """peptide_type -> set of sequences, plus target sequences in one list."""
    targets, entrapment = set(), set()
    with open(path, 'r', encoding='utf-8') as fh:
        fh.readline()
        for line in fh:
            f = line.rstrip('\n').split('\t')
            if len(f) < 5:
                continue
            if f[3] == 'target':
                targets.add(f[0])
            elif f[3] == 'p_target':
                entrapment.add(f[0])
    return targets, entrapment


def read_accepted(path):
    """Accepted stripped sequences, and the accepted entrapment subset."""
    doc = json.load(open(path, 'r', encoding='utf-8'))
    info = doc['info']
    accepted, accepted_entrapment = set(), set()
    for _eid, rec in info.items():
        seq = strip_sequence(rec[0])
        prot = rec[1] or ''
        if not seq or prot.startswith('decoy_') or 'decoy_' in prot.split(';')[0]:
            continue
        accepted.add(seq)
        if '_p_target' in prot:
            accepted_entrapment.add(seq)
    return accepted, accepted_entrapment


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('manifest')
    ap.add_argument('arm_json')
    ap.add_argument('--overlap', type=float, default=0.70)
    ap.add_argument('--mass-tol', type=float, default=0.01)
    a = ap.parse_args()

    targets, _ = read_manifest(a.manifest)
    accepted, accepted_entrapment = read_accepted(a.arm_json)
    print(f'library targets        : {len(targets):,}')
    print(f'accepted sequences     : {len(accepted):,}')
    print(f'accepted entrapment    : {len(accepted_entrapment):,}')

    pairs = sorted((neutral_mass(t), t) for t in targets if neutral_mass(t) is not None)
    masses = [p[0] for p in pairs]
    seqs = [p[1] for p in pairs]

    # Per length: [shadow entrapment, shadowed-target-accepted, control window targets,
    #              control accepted]
    stats = {}
    examples = []
    for ent in sorted(accepted_entrapment):
        m = neutral_mass(ent)
        if m is None:
            continue
        lo = bisect.bisect_left(masses, m - a.mass_tol)
        shadowed, control = [], []
        i = lo
        while i < len(masses) and masses[i] <= m + a.mass_tol:
            t = seqs[i]
            if t != ent:
                (shadowed if overlap(t, ent) > a.overlap else control).append(t)
            i += 1
        if not shadowed:
            continue
        n = len(ent)
        s = stats.setdefault(n, [0, 0, 0, 0])
        s[0] += 1
        hit = any(t in accepted for t in shadowed)
        if hit:
            s[1] += 1
        s[2] += len(control)
        s[3] += sum(1 for t in control if t in accepted)
        if hit and len(examples) < 12:
            examples.append((n, ent, next(t for t in shadowed if t in accepted)))

    print(f'\nAccepted entrapment that shadows a target, by length.')
    print(f'  "shadowed accepted"  = its shadowed target was ALSO accepted')
    print(f'  "control accepted"   = accepted rate of the NON-shadowed targets in the SAME')
    print(f'                         isobaric window - mass-matched, differing only in overlap')
    print(f'\n  {"len":>4} {"shadows":>8} {"shadowed acc":>13} {"control acc":>20} {"odds":>7}')
    tot = [0, 0, 0, 0]
    for n in sorted(stats):
        s = stats[n]
        for k in range(4):
            tot[k] += s[k]
        p_hit = s[1] / s[0] if s[0] else 0.0
        p_ctl = s[3] / s[2] if s[2] else 0.0
        odds = (p_hit / p_ctl) if p_ctl else float('inf')
        print(f'  {n:>4} {s[0]:>8} {s[1]:>6} ({p_hit:>6.1%}) {s[3]:>8}/{s[2]:<8} ({p_ctl:>6.1%})'
              f' {odds:>6.1f}x')
    p_hit = tot[1] / tot[0] if tot[0] else 0.0
    p_ctl = tot[3] / tot[2] if tot[2] else 0.0
    odds = (p_hit / p_ctl) if p_ctl else float('inf')
    print(f'  {"ALL":>4} {tot[0]:>8} {tot[1]:>6} ({p_hit:>6.1%}) {tot[3]:>8}/{tot[2]:<8}'
          f' ({p_ctl:>6.1%}) {odds:>6.1f}x')

    print('\nHow to read it: an odds ratio near 1 in a length bucket means those detections are')
    print('NOT shadowing-driven, so gating that bucket removes valid false-discovery models.')
    print('An odds ratio well above 1 means the entrapment is riding the target\'s signal.')
    if examples:
        print('\nexamples (length, accepted entrapment, accepted target it shadows):')
        for n, e, t in examples:
            print(f'  {n:>3}  {e}\t{t}')


if __name__ == '__main__':
    main()
