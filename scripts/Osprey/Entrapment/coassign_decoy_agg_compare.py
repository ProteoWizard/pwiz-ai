"""Where do the decoys go between pass 1 and pass 2 at EXPERIMENT scope?

Pass 1 admits 468 decoys at boundary 0.0120; pass 2 admits 71 at 0.012008 - the same bar.
So the boundary is not the cause. This compares each decoy precursor's experiment aggregate
score in the 1st-pass sidecar against the 2nd-pass sidecar to find what actually changed.
"""
import glob
import os
import struct
import sys

HEADER_LEN = 32
DECOY_BIT = 0x80000000
FDR = 0.01
OFF_EXP_PREC_Q = 28
OFF_EXP_AGG = 60


def read(path, record_len):
    with open(path, 'rb') as fh:
        data = fh.read()
    n = struct.unpack_from('<Q', data, 16)[0]
    for i in range(n):
        off = HEADER_LEN + i * record_len
        yield (struct.unpack_from('<I', data, off)[0],
               struct.unpack_from('<d', data, off + OFF_EXP_PREC_Q)[0],
               struct.unpack_from('<d', data, off + OFF_EXP_AGG)[0])


def reduce_files(paths, record_len):
    agg, q = {}, {}
    for p in paths:
        for eid, eq, ea in read(p, record_len):
            if eid not in agg or ea > agg[eid]:
                agg[eid] = ea
            if eid not in q or eq < q[eid]:
                q[eid] = eq
    return agg, q


def main(folder):
    p1 = sorted(glob.glob(os.path.join(folder, '*.1st-pass.fdr_scores.bin')))
    p2 = sorted(glob.glob(os.path.join(folder, '*.2nd-pass.fdr_scores.bin')))
    agg1, q1 = reduce_files(p1, 68)
    agg2, q2 = reduce_files(p2, 68)

    d1 = {e for e in agg1 if e & DECOY_BIT}
    d2 = {e for e in agg2 if e & DECOY_BIT}
    print('distinct DECOY precursors: 1st-pass %d, 2nd-pass %d, common %d'
          % (len(d1), len(d2), len(d1 & d2)))

    b1 = min(agg1[e] for e in agg1 if not (e & DECOY_BIT) and q1.get(e, 1.0) <= FDR)
    b2 = min(agg2[e] for e in agg2 if not (e & DECOY_BIT) and q2.get(e, 1.0) <= FDR)
    print('experiment boundary: pass1 %.6f, pass2 %.6f' % (b1, b2))
    print('decoys clearing own boundary: pass1 %d, pass2 %d'
          % (sum(1 for e in d1 if agg1[e] >= b1), sum(1 for e in d2 if agg2[e] >= b2)))

    zero2 = sum(1 for e in d2 if agg2[e] == 0.0)
    print('')
    print('2nd-pass decoys with aggregate EXACTLY 0.0 (ResetScores default): %d of %d'
          % (zero2, len(d2)))

    # Of the pass-1 decoys that cleared, what happened to each in pass 2?
    cleared1 = {e for e in d1 if agg1[e] >= b1}
    absent = sum(1 for e in cleared1 if e not in agg2)
    zeroed = sum(1 for e in cleared1 if e in agg2 and agg2[e] == 0.0)
    kept = sum(1 for e in cleared1 if e in agg2 and agg2[e] >= b2)
    lowered = sum(1 for e in cleared1
                  if e in agg2 and agg2[e] != 0.0 and agg2[e] < b2)
    print('')
    print('of the %d decoys that cleared at pass 1:' % len(cleared1))
    print('  absent from the 2nd-pass sidecar entirely : %d' % absent)
    print('  present but aggregate reset to 0.0        : %d' % zeroed)
    print('  present, non-zero, but now below the bar  : %d' % lowered)
    print('  still clearing at pass 2                  : %d' % kept)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
