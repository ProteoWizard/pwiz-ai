"""Turn the _runBest memory projection into a measurement.

CoAssignmentPassBuilder._runBest is Dictionary<int, Dictionary<uint,double>> - one inner
dictionary per FILE, keyed by every distinct entry_id that file's 1st-pass sidecar carries,
inserted with no q or class filter. It is never released after SealCutoffs.

This counts the real distinct entry_ids per file on the gate's 3-file Stellar run and scales to
82 files (SEA-AD) so the always-on panel's cost is a number rather than an estimate.
"""
import glob
import os
import struct
import sys

HEADER_LEN = 32
RECORD_LEN = 68

# .NET Dictionary<uint,double>: Entry is {int hashCode, int next, uint key, double value} = 24
# bytes with padding, plus the bucket array (one int per slot) and the usual ~1.4x slack from
# power-of-two-ish growth. 24 * 1.4 + 4 ~ 38; use 38 as a deliberately conservative per-entry
# figure and report the raw count too so the assumption can be replaced.
BYTES_PER_ENTRY = 38


def distinct_entry_ids(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    n = struct.unpack_from('<Q', data, 16)[0]
    seen = set()
    for i in range(n):
        seen.add(struct.unpack_from('<I', data, HEADER_LEN + i * RECORD_LEN)[0])
    return n, len(seen)


def main(folder, scale_to=82):
    paths = sorted(glob.glob(os.path.join(folder, '*.1st-pass.fdr_scores.bin')))
    if not paths:
        raise SystemExit('no 1st-pass sidecars under %s' % folder)

    total_distinct = 0
    for p in paths:
        rows, distinct = distinct_entry_ids(p)
        total_distinct += distinct
        print('  %-58s rows %9d  distinct entry_ids %8d'
              % (os.path.basename(p)[:58], rows, distinct))

    per_file = total_distinct / float(len(paths))
    measured_mb = total_distinct * BYTES_PER_ENTRY / 1024.0 / 1024.0
    scaled = per_file * scale_to
    scaled_gb = scaled * BYTES_PER_ENTRY / 1024.0 / 1024.0 / 1024.0

    print('')
    print('files measured           : %d' % len(paths))
    print('distinct entry_ids total : %d  (mean %0.0f per file)' % (total_distinct, per_file))
    print('_runBest live entries    : %d' % total_distinct)
    print('_runBest at %d bytes/entry: %.1f MB measured' % (BYTES_PER_ENTRY, measured_mb))
    print('')
    print('linear scale to %d files : %.0f entries, %.2f GB' % (scale_to, scaled, scaled_gb))
    print('(held from phase 1 through the whole panel build, alongside both accumulators)')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
