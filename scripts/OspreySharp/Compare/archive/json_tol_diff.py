"""Tolerance-based JSON diff.

Walks two JSON files in parallel and reports the max absolute
difference for every numeric leaf, plus any structural mismatches
(differing keys, differing types, differing list lengths, etc.).

Exit code 0 if all numeric leaves are within --tolerance and there
are no structural mismatches; 1 otherwise.

Usage:
    python json_tol_diff.py <a.json> <b.json> [--tolerance 1e-9]
"""
import argparse
import json
import math
import sys


def walk(a, b, path, tol, stats):
    if type(a) is not type(b):
        # int vs float is OK
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            pass
        else:
            stats["type_mismatch"].append((path, type(a).__name__, type(b).__name__))
            return

    if isinstance(a, dict):
        keys_a = set(a.keys())
        keys_b = set(b.keys())
        only_a = keys_a - keys_b
        only_b = keys_b - keys_a
        for k in sorted(only_a):
            stats["key_only_a"].append(f"{path}.{k}")
        for k in sorted(only_b):
            stats["key_only_b"].append(f"{path}.{k}")
        for k in sorted(keys_a & keys_b):
            walk(a[k], b[k], f"{path}.{k}", tol, stats)
    elif isinstance(a, list):
        if len(a) != len(b):
            stats["list_len_mismatch"].append((path, len(a), len(b)))
            n = min(len(a), len(b))
        else:
            n = len(a)
        for i in range(n):
            walk(a[i], b[i], f"{path}[{i}]", tol, stats)
    elif isinstance(a, (int, float)):
        # NaN handling
        if (isinstance(a, float) and math.isnan(a)) or (isinstance(b, float) and math.isnan(b)):
            if not (isinstance(a, float) and math.isnan(a) and isinstance(b, float) and math.isnan(b)):
                stats["nan_mismatch"].append((path, a, b))
            return
        diff = abs(float(a) - float(b))
        stats["n_numeric"] += 1
        if diff > stats["max_diff"]:
            stats["max_diff"] = diff
            stats["max_diff_path"] = path
            stats["max_diff_a"] = a
            stats["max_diff_b"] = b
        if diff > tol:
            stats["n_above_tol"] += 1
            if len(stats["above_tol_samples"]) < 10:
                stats["above_tol_samples"].append((path, a, b, diff))
    elif isinstance(a, str):
        if a != b:
            stats["n_string_diff"] += 1
            if len(stats["string_diff_samples"]) < 10:
                stats["string_diff_samples"].append((path, a, b))
    else:
        # bool, None
        if a != b:
            stats["n_other_diff"] += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--tolerance", type=float, default=1e-9)
    args = ap.parse_args()

    with open(args.a, "r", encoding="utf-8") as fa:
        a = json.load(fa)
    with open(args.b, "r", encoding="utf-8") as fb:
        b = json.load(fb)

    stats = {
        "n_numeric": 0,
        "n_above_tol": 0,
        "n_string_diff": 0,
        "n_other_diff": 0,
        "max_diff": 0.0,
        "max_diff_path": None,
        "max_diff_a": None,
        "max_diff_b": None,
        "above_tol_samples": [],
        "string_diff_samples": [],
        "key_only_a": [],
        "key_only_b": [],
        "list_len_mismatch": [],
        "type_mismatch": [],
        "nan_mismatch": [],
    }
    walk(a, b, "$", args.tolerance, stats)

    print(f"=== {args.a} vs {args.b} ===")
    print(f"tolerance: {args.tolerance:g}")
    print(f"numeric leaves: {stats['n_numeric']}")
    print(f"max_diff: {stats['max_diff']:.6e}  at  {stats['max_diff_path']}")
    print(f"  a={stats['max_diff_a']}  b={stats['max_diff_b']}")
    print(f"n_above_tol: {stats['n_above_tol']}")
    print(f"n_string_diff: {stats['n_string_diff']}")
    print(f"key_only_a: {len(stats['key_only_a'])}; key_only_b: {len(stats['key_only_b'])}")
    print(f"list_len_mismatch: {len(stats['list_len_mismatch'])}")
    print(f"type_mismatch: {len(stats['type_mismatch'])}")
    print(f"nan_mismatch: {len(stats['nan_mismatch'])}")

    if stats["above_tol_samples"]:
        print("\nFirst above-tolerance numeric divergences:")
        for path, va, vb, d in stats["above_tol_samples"]:
            print(f"  {path}: a={va} b={vb} diff={d:.6e}")

    if stats["string_diff_samples"]:
        print("\nFirst string divergences:")
        for path, va, vb in stats["string_diff_samples"]:
            print(f"  {path}: a={va!r} b={vb!r}")

    if stats["key_only_a"]:
        print(f"\nKeys only in {args.a} (first 10):")
        for k in stats["key_only_a"][:10]:
            print(f"  {k}")
    if stats["key_only_b"]:
        print(f"\nKeys only in {args.b} (first 10):")
        for k in stats["key_only_b"][:10]:
            print(f"  {k}")
    if stats["list_len_mismatch"]:
        print(f"\nList-length mismatches (first 10):")
        for path, la, lb in stats["list_len_mismatch"][:10]:
            print(f"  {path}: a={la} b={lb}")

    fail = (stats["n_above_tol"] > 0 or stats["n_string_diff"] > 0
            or stats["n_other_diff"] > 0
            or len(stats["key_only_a"]) > 0 or len(stats["key_only_b"]) > 0
            or len(stats["list_len_mismatch"]) > 0
            or len(stats["type_mismatch"]) > 0
            or len(stats["nan_mismatch"]) > 0)
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
