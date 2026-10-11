"""Replicate CV of Osprey peak areas, by abundance quartile, on the target precursors every arm
identifies: the Osprey counterpart of abundance_cv.py (which reads DIA-NN reports).

Identified = in the search's output.blib (accepted at the experiment's FDR). Area = peak_area in
each replicate run's <stem>.scores-reconciled.parquet (boundaries reconciled across runs). Only
precursors with a positive area in every replicate count. Quartiles come from the first arm's mean
area over the precursors all arms share.

Usage: python osprey_area_cv.py --runs EV13,EV14,EV15 <arm>=<search dir> [...]
  --runs: substrings picking the replicate runs' parquet files (default EV13,EV14,EV15).
"""
import argparse
import glob
import math
import os
import sqlite3
import statistics

import pyarrow.parquet as pq


def identified(search_dir):
    con = sqlite3.connect(os.path.join(search_dir, 'output.blib'))
    try:
        return {(seq, z) for seq, z in con.execute('select peptideModSeq, precursorCharge from RefSpectra')}
    finally:
        con.close()


def areas(search_dir, run):
    files = [f for f in glob.glob(os.path.join(search_dir, '*.scores-reconciled.parquet')) if run in os.path.basename(f)]
    if len(files) != 1:
        raise SystemExit('%s: expected one reconciled parquet matching %r, found %d' % (search_dir, run, len(files)))
    t = pq.read_table(files[0], columns=['modified_sequence', 'charge', 'is_decoy', 'peak_area']).to_pydict()
    out = {}
    for seq, z, decoy, area in zip(t['modified_sequence'], t['charge'], t['is_decoy'], t['peak_area']):
        if not decoy and area is not None and area > 0:
            out[(seq, z)] = area
    return out


def cv(values):
    m = statistics.fmean(values)
    return statistics.stdev(values) / m if m > 0 else math.nan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--runs', default='EV13,EV14,EV15')
    ap.add_argument('arms', nargs='+')
    a = ap.parse_args()
    runs = [r for r in a.runs.split(',') if r]
    arms = []
    for spec in a.arms:
        name, path = spec.split('=', 1)
        ids = identified(path)
        per_run = [areas(path, r) for r in runs]
        quant = {k: [pr[k] for pr in per_run] for k in ids if all(k in pr for pr in per_run)}
        arms.append((name, len(ids), quant))
        print('%-24s identified %6d; quantified in all %d runs %6d' % (name, len(ids), len(runs), len(quant)))

    shared = set.intersection(*(set(q) for _, _, q in arms))
    first = arms[0][2]
    ordered = sorted(shared, key=lambda k: statistics.fmean(first[k]))
    n = len(ordered)
    bounds = [ordered[i * n // 4:(i + 1) * n // 4] for i in range(4)]
    labels = ['Q1 (low)', 'Q2', 'Q3', 'Q4 (high)']
    print('\n%d precursors shared by every arm; quartiles of %s mean area; median CV' % (n, arms[0][0]))
    print('%-10s %6s ' % ('quartile', 'n') + ' '.join('%14s' % name[:14] for name, _, _ in arms))
    for label, keys in zip(labels, bounds):
        print('%-10s %6d ' % (label, len(keys)) +
              ' '.join('%14.3f' % statistics.median(cv(q[k]) for k in keys) for _, _, q in arms))
    print('%-10s %6d ' % ('all', n) + ' '.join('%14.3f' % statistics.median(cv(q[k]) for k in ordered) for _, _, q in arms))
    print('\nEach arm on all its own quantified precursors (median CV):')
    for name, _, q in arms:
        print('  %-24s %6d  %.3f' % (name, len(q), statistics.median(cv(v) for v in q.values())))


if __name__ == '__main__':
    main()
