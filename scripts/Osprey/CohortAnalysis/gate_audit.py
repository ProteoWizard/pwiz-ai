#!/usr/bin/env python3
"""Can an entrapment oracle even SEE the errors a protein-level prior admits?

`protein-compact` expands the reported set to the peptides of every protein detected in the
first pass with >= 2 distinct peptides. Entrapment peptides carry foreign/shuffled sequences that
do not belong to a biologically coherent protein, so they may be unable to clear that gate at
anything like the rate real proteins do. If so, the expansion is entrapment-depleted BY
CONSTRUCTION and its measured FDP is biased low - the oracle cannot audit the very population the
method adds. (See the validity argument in TODO-20260727_osprey_pass2_fdr_default.md: "Pairing
gives matched COUNTS, not exchangeability".)

Reads FDRBench-format TSVs (peptide / mod_peptide / charge / q_value / score / protein) from two
run directories and reports:
  1. accepted counts + entrapment FDP per mode, as a check against the recorded numbers
  2. the >= 2-peptide gate rate for REAL vs ENTRAPMENT proteins - the structural asymmetry
  3. the entrapment rate of rows one mode reports and the other does not (the expansion)

Usage:
  python gate_audit.py <dirA> <dirB>       (default: the recorded 82-file 4-way pair)
"""
import collections
import csv
import os
import sys

RUNS = os.environ.get('OSPREY_RUNS_DIR', 'D:/test/Pilot-MTG-Tissue-May2026/runs')
ENTRAP_TAG = '_p_target'          # entrapment accessions carry this suffix
RATIO = 0.97                      # entrapment : target library ratio for this dataset


def is_entrap(protein):
    return ENTRAP_TAG in protein


def load(run_dir):
    """[(peptide, charge, q, protein, is_entrap)] from a run's fdrbench.tsv."""
    path = os.path.join(run_dir, 'fdrbench.tsv')
    rows = []
    with open(path, encoding='utf-8', newline='') as fh:
        for r in csv.DictReader(fh, delimiter='\t'):
            rows.append((r['peptide'], r['charge'], float(r['q_value']), r['protein'],
                         is_entrap(r['protein'])))
    return rows


def fdp(n_entrap, n_total):
    """The combined entrapment estimator Osprey uses: (1 + 1/r) * entrap / total."""
    return (1.0 + 1.0 / RATIO) * n_entrap / n_total if n_total else float('nan')


def summarize(name, rows, q_cut=0.01):
    acc = [r for r in rows if r[2] <= q_cut]
    ent = sum(1 for r in acc if r[4])
    print(f'{name:<18} reported {len(rows):>9,}   accepted@{q_cut:.0%} {len(acc):>8,}   '
          f'entrapment {ent:>6,}   FDP {100 * fdp(ent, len(acc)):>5.2f}%')
    return acc


def gate_audit(acc, label):
    """How many proteins reach the >= 2 distinct peptide gate, real vs entrapment?"""
    peps = collections.defaultdict(set)
    for pep, _chg, _q, prot, _e in acc:
        for p in prot.split(';'):
            peps[p].add(pep)
    real = {p: v for p, v in peps.items() if not is_entrap(p)}
    ent = {p: v for p, v in peps.items() if is_entrap(p)}
    print(f'\n  {label}: proteins with >=1 accepted peptide - '
          f'real {len(real):,}   entrapment {len(ent):,}')
    for nm, grp in (('real', real), ('entrapment', ent)):
        if not grp:
            continue
        ge2 = sum(1 for v in grp.values() if len(v) >= 2)
        ge3 = sum(1 for v in grp.values() if len(v) >= 3)
        peptides_in_ge2 = sum(len(v) for v in grp.values() if len(v) >= 2)
        print(f'    {nm:<11} >=2 peptides: {ge2:>7,} ({100 * ge2 / len(grp):5.1f}% of its '
              f'proteins)   >=3: {ge3:>7,} ({100 * ge3 / len(grp):5.1f}%)   '
              f'peptides inside >=2 proteins: {peptides_in_ge2:,}')
    if real and ent:
        rr = sum(1 for v in real.values() if len(v) >= 2) / len(real)
        er = sum(1 for v in ent.values() if len(v) >= 2) / len(ent)
        print(f'    -> a real protein is {rr / er if er else float("inf"):.1f}x more likely to '
              f'clear the >=2-peptide gate than an entrapment "protein"'
              if er else '    -> NO entrapment protein clears the gate at all')


def main():
    a_dir = sys.argv[1] if len(sys.argv) > 2 else os.path.join(RUNS, 'pass2-82-4way-protein-compact')
    b_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(RUNS, 'pass2-82-4way-transfer-compete')
    a, b = load(a_dir), load(b_dir)
    print('=== 1. accepted sets and entrapment FDP ===')
    acc_a = summarize(os.path.basename(a_dir)[-16:], a)
    acc_b = summarize(os.path.basename(b_dir)[-16:], b)

    print('\n=== 2. the >=2-peptide gate: can entrapment proteins clear it? ===')
    gate_audit(acc_a, os.path.basename(a_dir)[-16:])
    gate_audit(acc_b, os.path.basename(b_dir)[-16:])

    print('\n=== 3. rows one mode reports and the other does not ===')
    key_b = {(r[0], r[1]) for r in b}
    only_a = [r for r in a if (r[0], r[1]) not in key_b]
    key_a = {(r[0], r[1]) for r in a}
    only_b = [r for r in b if (r[0], r[1]) not in key_a]
    for nm, rows in ((f'only in {os.path.basename(a_dir)[-16:]}', only_a),
                     (f'only in {os.path.basename(b_dir)[-16:]}', only_b)):
        if not rows:
            print(f'  {nm}: none')
            continue
        ent = sum(1 for r in rows if r[4])
        acc = [r for r in rows if r[2] <= 0.01]
        ent_acc = sum(1 for r in acc if r[4])
        print(f'  {nm}: {len(rows):>9,} rows, entrapment {100 * ent / len(rows):5.2f}%   '
              f'| accepted@1% {len(acc):>7,}, entrapment {ent_acc:>5,} '
              f'({100 * ent_acc / len(acc) if acc else 0:5.2f}%, FDP {100 * fdp(ent_acc, len(acc)):5.2f}%)')


if __name__ == '__main__':
    raise SystemExit(main())
