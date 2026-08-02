#!/usr/bin/env python3
"""Does any entrapment sequence also appear in the TARGET set of the same library?

An entrapment peptide is only a valid model of a false discovery if it is ABSENT from the
sample. Two distinct ways that can fail, one per entrapment strategy:

  * shuffle entrapment -- an anagram can collide with a genuinely different human tryptic
    peptide by chance, so the "entrapment" is really a target under another name;
  * foreign-species (Arabidopsis) entrapment -- plant and human share conserved proteins, so
    a tryptic peptide from a conserved region can be BYTE-IDENTICAL to a human one and hence
    genuinely present in a human sample.

The second is the one worth worrying about here, and it cuts the opposite way from the effect
the gate fixes: a colliding entrapment is detected wherever its human twin is, which inflates
measured FDP. Fragment-overlap gating does NOT catch it -- an exact collision has overlap 1.0
against a DIFFERENT target, while the gate only compares each entrapment to its own paired
target.

Reports the collision count and rate per library, plus a sample, so an arm's FDP can be
corrected or at least caveated. Sequence comparison is on the stripped sequence as the manifest
stores it.

    python entrapment_target_collision.py <pairing.tsv> [<pairing.tsv> ...]
"""
import os
import sys


def load(path):
    """(target sequence set, entrapment sequence list) from a pairing manifest."""
    targets, entrap = set(), []
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {name: i for i, name in enumerate(header)}
        i_seq, i_type = col['sequence'], col['peptide_type']
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) <= i_type:
                continue
            t = p[i_type]
            if t == 'target':
                targets.add(p[i_seq])
            elif t == 'p_target':
                entrap.append(p[i_seq])
    return targets, entrap


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    for path in sys.argv[1:]:
        label = os.path.basename(os.path.dirname(path))
        targets, entrap = load(path)
        tset = targets
        hits = [s for s in entrap if s in tset]
        # Distinct sequences matter more than rows: the same colliding sequence can appear at
        # several charge states, and it is one contaminated peptide either way.
        uniq_hits = sorted(set(hits))
        print(f'{label}')
        print(f'  targets {len(tset):>10,}   entrapment rows {len(entrap):>10,}   '
              f'distinct entrapment {len(set(entrap)):>10,}')
        print(f'  entrapment sequences ALSO IN the target set: '
              f'{len(uniq_hits):,} distinct  ({len(uniq_hits)/max(len(set(entrap)),1)*100:.4f}%)')
        for s in uniq_hits[:12]:
            print(f'    {s}')
        if len(uniq_hits) > 12:
            print(f'    ... and {len(uniq_hits)-12:,} more')
        print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
