"""Compare a Rust and a C# <stem>.calibration.json by content.

usage: python calibration_diff.py <rust.json> <csharp.json>

Exit 0 when the calibrations agree, 1 when they differ (the first differences are printed), 2 on
a read error.

The two files were never byte-comparable: C# writes its validity stamp first (osprey_validity),
and both sides record when the calibration ran (metadata.timestamp). C# also writes
model_diagnostics (2026-10-17), the run's row of the model diagnostics report's calibration view,
which has no Rust counterpart. Those three are removed from both sides; every calibration value
is compared exactly. JSON numbers parse to the same float on both sides because both writers emit
round-trip decimal forms.
"""
import json
import sys

from reconciliation_diff import diff

DROPPED = ('osprey_validity', 'model_diagnostics')
DROPPED_METADATA = ('timestamp',)


def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        doc = json.load(f)
    for key in DROPPED:
        doc.pop(key, None)
    metadata = doc.get('metadata')
    if isinstance(metadata, dict):
        for key in DROPPED_METADATA:
            metadata.pop(key, None)
    return doc


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    try:
        rust = load(sys.argv[1])
        cs = load(sys.argv[2])
    except (OSError, ValueError) as ex:
        print(f'read error: {ex}')
        return 2
    out = []
    diff(rust, cs, '$', out)
    if not out:
        print('calibrations agree')
        return 0
    for line in out:
        print(line)
    return 1


if __name__ == '__main__':
    sys.exit(main())
