"""Reproduce the pass-2 experiment-scope decoy count from the 2nd-pass sidecars alone.

Falsifiable test of one hypothesis: the pass-2 experiment acceptance boundary is drawn from
PASS-1 aggregate scores against a PASS-2 acceptance set, because the default pass-2 mode
(protein-compact) recomputes experiment q from a fresh competition while
ExperimentAggregateScore stays the carried pass-1 value.

If that is the mechanism, computing
    boundary = min(exp_agg) over precursors with exp_prec_q <= 0.01, non-decoy
    decoys    = |{decoy precursors with exp_agg >= boundary}|
straight from the 2nd-pass sidecars must reproduce the panel's 71, and the boundary must sit
ABOVE pass 1's 0.0120 (a higher bar admitting fewer decoys).

Run: python coassign_pass2_boundary.py <dir-with-*.fdr_scores.bin>
"""
import glob
import os
import struct
import sys

HEADER_LEN = 32
RECORD_LEN = 68
DECOY_BIT = 0x80000000
FDR = 0.01

OFF_ENTRY_ID = 0
OFF_EXP_PREC_Q = 28
OFF_EXP_AGG = 60


def read_records(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    if len(data) < HEADER_LEN:
        raise SystemExit('%s: shorter than the header' % path)
    version = data[8]
    n = struct.unpack_from('<Q', data, 16)[0]
    expected = HEADER_LEN + n * RECORD_LEN
    if version != 4 or len(data) != expected:
        raise SystemExit('%s: version %d, %d bytes, expected %d at the v4 stride'
                         % (path, version, len(data), expected))
    for i in range(n):
        off = HEADER_LEN + i * RECORD_LEN
        yield (struct.unpack_from('<I', data, off + OFF_ENTRY_ID)[0],
               struct.unpack_from('<d', data, off + OFF_EXP_PREC_Q)[0],
               struct.unpack_from('<d', data, off + OFF_EXP_AGG)[0])


def main(folder):
    paths = sorted(glob.glob(os.path.join(folder, '*.2nd-pass.fdr_scores.bin')))
    if not paths:
        raise SystemExit('no 2nd-pass sidecars under %s' % folder)

    # Experiment scope is pooled across runs, so reduce per precursor across every file.
    # exp_agg is a per-entry roll-up, identical in every record of that entry; max is the
    # defensive reducer (0.0 is the ResetScores default and sits mid distribution).
    best_agg = {}
    best_q = {}
    for path in paths:
        for entry_id, exp_q, exp_agg in read_records(path):
            if entry_id not in best_agg or exp_agg > best_agg[entry_id]:
                best_agg[entry_id] = exp_agg
            if entry_id not in best_q or exp_q < best_q[entry_id]:
                best_q[entry_id] = exp_q
        print('  read %-70s' % os.path.basename(path))

    accepted = [e for e, q in best_q.items() if q <= FDR and not (e & DECOY_BIT)]
    if not accepted:
        raise SystemExit('no accepted non-decoy precursors at q <= %g' % FDR)
    boundary = min(best_agg[e] for e in accepted)

    decoys = [e for e in best_agg if (e & DECOY_BIT) and best_agg[e] >= boundary]
    nondecoys = [e for e in best_agg if not (e & DECOY_BIT) and best_agg[e] >= boundary]

    print('')
    print('accepted non-decoy precursors (exp q <= %g): %d' % (FDR, len(accepted)))
    print('pass-2 experiment boundary (min carried pass-1 aggregate): %.6f' % boundary)
    print('pass-1 experiment boundary, for comparison:                0.012000')
    print('')
    print('decoy precursors clearing it:     %d   (panel reports 71)' % len(decoys))
    print('non-decoy precursors clearing it: %d' % len(nondecoys))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
