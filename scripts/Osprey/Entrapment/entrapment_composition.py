#!/usr/bin/env python3
"""Is the entrapment pool length- and composition-matched to the targets it models?

An entrapment peptide is only a fair model of a false target if it is as HARD to match as a
real absent peptide. Two entrapment designs differ fundamentally here, and the difference is
structural rather than incidental:

  * shuffle entrapment is an ANAGRAM of its own target, so its length and amino-acid
    composition are identical to the target set BY CONSTRUCTION - it cannot be skewed;
  * foreign-species (Arabidopsis) entrapment is drawn from a different proteome, so nothing
    forces its length or composition to match, and reaching a 1:1 ratio may require taking
    whatever peptides are available.

This matters because short peptides carry fewer fragment ions and are matched spuriously more
often. An entrapment pool skewed short would report a HIGHER false-discovery proportion than
the target population actually experiences - inflating measured FDP for a reason that has
nothing to do with the search being wrong.

    python entrapment_composition.py <pairing.tsv> [<pairing.tsv> ...]
"""
import os
import sys
from collections import Counter


def summarise(path):
    lens = {'target': Counter(), 'p_target': Counter()}
    aa = {'target': Counter(), 'p_target': Counter()}
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {n: i for i, n in enumerate(header)}
        i_seq, i_type = col['sequence'], col['peptide_type']
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) <= i_type:
                continue
            t = p[i_type]
            if t in lens:
                s = p[i_seq]
                lens[t][len(s)] += 1
                aa[t].update(s)
    return lens, aa


def stats(counter):
    n = sum(counter.values())
    if not n:
        return 0, 0.0, 0, 0
    mean = sum(k * v for k, v in counter.items()) / n
    ordered = sorted(counter.items())
    cum, med, p10 = 0, None, None
    for k, v in ordered:
        cum += v
        if p10 is None and cum >= 0.10 * n:
            p10 = k
        if med is None and cum >= 0.50 * n:
            med = k
    return n, mean, med, p10


def main():
    for path in sys.argv[1:]:
        label = os.path.basename(os.path.dirname(path))
        lens, aa = summarise(path)
        print(label)
        for t in ('target', 'p_target'):
            n, mean, med, p10 = stats(lens[t])
            short = sum(v for k, v in lens[t].items() if k <= 8)
            print(f'  {t:<9} n={n:>10,}  mean len {mean:6.3f}  median {med}  p10 {p10}  '
                  f'len<=8 {short/max(n,1)*100:5.2f}%')
        nt, np_ = sum(aa['target'].values()), sum(aa['p_target'].values())
        if nt and np_:
            # Largest composition shifts, in percentage points of total residues. Shuffle
            # entrapment must score 0.000 here; anything else is a foreign-pool skew.
            diffs = sorted(((aa['p_target'][c] / np_ - aa['target'][c] / nt) * 100.0, c)
                           for c in set(aa['target']) | set(aa['p_target']))
            worst = sorted(diffs, key=lambda d: -abs(d[0]))[:6]
            print('  composition shift (entrapment - target, pct points of residues): '
                  + '  '.join(f'{c}{d:+.3f}' for d, c in worst))
        print()


if __name__ == '__main__':
    main()
