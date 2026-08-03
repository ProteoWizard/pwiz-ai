#!/usr/bin/env python3
"""How often does an accepted precursor share a chromatographic peak with a better-scoring one?

Motivated by a tool-wide concern: DIA search can assign two IDs to a single chromatographic
feature without sequence-specific differentiating evidence. Normally that is unfalsifiable -
there is no ground truth about which of two co-eluting isobaric IDs is real. Entrapment gives a
naturally labelled case: entrapment peptides are ABSENT by construction, so an entrapment sharing
a peak with a better-scoring target is a demonstrated false co-assignment.

Requires NO knowledge of the sequence relationship. Two precursors share a peak when they are in
the same run, at the same apex RT, and close enough in precursor mass to be co-isolated. The
ortholog and I/L cases were found by sequence similarity; this finds the same phenomenon by
geometry, so it generalises to relationships nobody has thought to look for.

The accepted-TARGET rate is reported alongside as the background: targets co-assign with each
other too (paralogs, isoforms), and only the excess over that background is entrapment-specific.

    python peak_coassignment.py <arm.json> [--rt 0.05] [--mass 0.01]
"""
import argparse
import bisect
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from contamination_corrected import AA, H2O                  # noqa: E402


def mass(s):
    return sum(AA.get(c, 0.0) for c in s) + H2O


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('arm')
    ap.add_argument('--rt', type=float, default=0.05, help='apex RT tolerance, minutes')
    ap.add_argument('--mass', type=float, default=0.01, help='precursor mass tolerance, Da')
    ap.add_argument('--qcut', type=float, default=0.01)
    a = ap.parse_args()

    d = json.load(open(a.arm))
    info, peaks = d['info'], d['peaks']

    # Accepted, split by class. Decoys excluded: they are not competing for a real peak in the
    # sense being measured, and including them would double-count the same feature.
    ent, tgt = [], []
    for eid, (seq, pro, q) in info.items():
        p = pro or ''
        if 'decoy' in p.lower() or q > a.qcut:
            continue
        (ent if '_p_target' in p else tgt).append((eid, seq, q, mass(seq)))

    # Per-file index of accepted targets, sorted by apex RT for binary search.
    byfile = {}
    for eid, seq, q, m in tgt:
        for f, rt in peaks.get(eid, {}).items():
            byfile.setdefault(f, []).append((rt, m, q, seq))
    for f in byfile:
        byfile[f].sort()

    def scan(rows, label):
        n_prec = n_hit = 0
        n_better = 0
        for eid, seq, q, m in rows:
            hit = better = False
            for f, rt in peaks.get(eid, {}).items():
                arr = byfile.get(f)
                if not arr:
                    continue
                lo = bisect.bisect_left(arr, (rt - a.rt, -1e9, -1e9, ''))
                hi = bisect.bisect_right(arr, (rt + a.rt, 1e9, 1e9, '￿'))
                for i in range(lo, hi):
                    rt2, m2, q2, s2 = arr[i]
                    if s2 == seq or abs(m2 - m) > a.mass:
                        continue
                    hit = True
                    if q2 < q:
                        better = True
            n_prec += 1
            n_hit += hit
            n_better += better
        print('  %-22s n=%5d   shares a peak with an accepted target: %4d (%5.1f%%)   '
              'of which BETTER-scoring: %4d (%5.1f%%)'
              % (label, n_prec, n_hit, n_hit / max(n_prec, 1) * 100,
                 n_better, n_better / max(n_prec, 1) * 100))

    print('%s   (RT +-%.3f min, mass +-%.3f Da, q<=%.3g)'
          % (os.path.basename(a.arm), a.rt, a.mass, a.qcut))
    scan(ent, 'ENTRAPMENT (absent)')
    scan(tgt, 'TARGET (background)')


if __name__ == '__main__':
    main()
