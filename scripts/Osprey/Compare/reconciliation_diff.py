"""Compare a Rust and a C# <stem>.reconciliation.json by content.

usage: python reconciliation_diff.py <rust.json> <csharp.json>

Exit 0 when the plans agree, 1 when they differ (the first differences are printed), 2 on a
read error.

The two files are no longer byte-comparable. C# writes the validity stamp first
(osprey_validity), and its format v4 (2026-10-16) dropped four fields Rust's v3 still writes
because they were identical in every run's file and nothing read them: file_stems,
first_pass_base_ids, library_hash, search_hash. Those fields, the stamp and format_version are
removed from both sides; every action, gap-fill target and refined-calibration value is still
compared exactly. JSON numbers parse to the same float on both sides because both writers emit
round-trip decimal forms.
"""
import json
import sys

DROPPED = ('osprey_validity', 'file_stems', 'first_pass_base_ids', 'library_hash',
           'search_hash', 'format_version')


def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        doc = json.load(f)
    for key in DROPPED:
        doc.pop(key, None)
    return doc


def diff(a, b, where, out, limit=10):
    if len(out) >= limit:
        return
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                out.append(f'{where}.{key}: present on one side only')
            else:
                diff(a[key], b[key], f'{where}.{key}', out, limit)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append(f'{where}: length {len(a)} vs {len(b)}')
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, f'{where}[{i}]', out, limit)
    elif a != b:
        out.append(f'{where}: {a!r} vs {b!r}')


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
        print('reconciliation plans agree')
        return 0
    for line in out:
        print(line)
    return 1


if __name__ == '__main__':
    sys.exit(main())
