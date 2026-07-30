#!/usr/bin/env python3
"""Reductio: accept at q<=5%, then re-compete using ONLY the paired decoys of accepted targets.

Brendan's argument, made concrete. A target clears a threshold largely BY BEATING ITS OWN DECOY,
so conditioning on the target's acceptance conditions its paired decoy to be the losing draw.
Re-competing inside that subset therefore faces a null depleted exactly at the high end: reported
q falls and acceptances rise WITHOUT ANY NEW EVIDENCE. The selection has no biological content at
all - it is protein-compact's failure mode with the protein story removed.

The simulation is driven by this dataset's measured pass-1 score histograms (target / decoy) and
its measured false fraction (densityRatio.plateauRatio), and because it is a simulation we know
which precursors are truly false - so we can report what the recalibrated q CLAIMS versus what is
actually true.

Usage: python paired_recal_demo.py [run-dir-name] [--q-gate 0.05] [--n 400000]
"""
import argparse
import os

import numpy as np

import mbn_surface as M


def sample_from_hist(counts, edges, n, rng):
    """Draw n scores from an empirical histogram (uniform within each bin)."""
    counts = np.asarray(counts, dtype=float)
    counts[counts < 0] = 0.0
    if counts.sum() <= 0:
        raise SystemExit('empty histogram')
    p = counts / counts.sum()
    centers = rng.choice(len(counts), size=n, p=p)
    lo = np.asarray(edges[:-1], dtype=float)[centers]
    hi = np.asarray(edges[1:], dtype=float)[centers]
    return lo + rng.random(n) * (hi - lo)


def tdc_q(scores, is_decoy):
    """Standard 1:1 target-decoy q: at each score, (#decoys >= s) / (#targets >= s), made
    monotone from the low-score end. Returns q per entry (decoys included, q meaningless there)."""
    order = np.argsort(-scores, kind='stable')
    dec = is_decoy[order].astype(np.int64)
    tgt = 1 - dec
    cum_d = np.cumsum(dec)
    cum_t = np.cumsum(tgt)
    with np.errstate(divide='ignore', invalid='ignore'):
        fdr = np.where(cum_t > 0, cum_d / np.maximum(cum_t, 1), 1.0)
    q_sorted = np.minimum.accumulate(fdr[::-1])[::-1]      # monotone in score
    q = np.empty_like(q_sorted)
    q[order] = q_sorted
    return q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run', nargs='?', default='pass2-82-4way-protein-compact')
    ap.add_argument('--q-gate', type=float, default=0.05)
    ap.add_argument('--n', type=int, default=400000)
    ap.add_argument('--seed', type=int, default=20260730)
    args = ap.parse_args()

    j = M.load(os.path.join(M.RUNS, args.run))
    sc = (j or {}).get('scores') or {}
    edges = sc.get('binEdges')
    if not edges:
        raise SystemExit(f'no score histogram in {args.run}')
    pi0 = ((j.get('densityRatio') or {}).get('plateauRatio')) or 0.9
    rng = np.random.default_rng(args.seed)

    # Null = the measured decoy distribution. The true-positive component is the part of the
    # target histogram that the null does not explain, at the measured false fraction.
    decoy_h = np.asarray(sc['decoy'], dtype=float)
    target_h = np.asarray(sc['target'], dtype=float)
    scale = target_h.sum() / max(decoy_h.sum(), 1.0)
    true_h = np.clip(target_h - pi0 * scale * decoy_h, 0, None)

    n_false = int(args.n * pi0)
    n_true = args.n - n_false
    print(f'run {args.run}: measured false fraction (plateauRatio) {pi0:.3f} -> simulating '
          f'{n_true:,} true and {n_false:,} false targets, each with its paired decoy')

    # Truly-false targets and ALL decoys are draws from the same null (equal chance holds here
    # BY CONSTRUCTION - so any inflation below comes purely from the selection, not from a
    # violated assumption).
    t_false = sample_from_hist(decoy_h, edges, n_false, rng)
    t_true = sample_from_hist(true_h, edges, n_true, rng)
    t_scores = np.concatenate([t_true, t_false])
    t_is_false = np.concatenate([np.zeros(n_true, bool), np.ones(n_false, bool)])
    d_scores = sample_from_hist(decoy_h, edges, args.n, rng)      # one paired decoy per target

    allsc = np.concatenate([t_scores, d_scores])
    isdec = np.concatenate([np.zeros(args.n, bool), np.ones(args.n, bool)])
    q_all = tdc_q(allsc, isdec)[:args.n]

    base = q_all <= 0.01
    print(f'\nBASELINE full competition:      accepted@1% {base.sum():>7,}   '
          f'true FDP {100 * t_is_false[base].mean():5.2f}%')

    # The manipulation: keep targets that cleared the gate, and ONLY their paired decoys.
    gate = q_all <= args.q_gate
    print(f'gate: accepted@{args.q_gate:.0%} {gate.sum():>7,}   '
          f'true FDP {100 * t_is_false[gate].mean():5.2f}%   '
          f'(their paired decoys are the only null retained)')

    sub_sc = np.concatenate([t_scores[gate], d_scores[gate]])
    sub_dec = np.concatenate([np.zeros(gate.sum(), bool), np.ones(gate.sum(), bool)])
    q_sub = tdc_q(sub_sc, sub_dec)[:gate.sum()]
    sub_false = t_is_false[gate]

    acc = q_sub <= 0.01
    print(f'AFTER paired-decoy re-competition: accepted@1% {acc.sum():>7,}   '
          f'true FDP {100 * sub_false[acc].mean():5.2f}%')
    print(f'\n  -> acceptances {100 * (acc.sum() - base.sum()) / max(base.sum(), 1):+.1f}% '
          f'on IDENTICAL evidence; the reported q still says 1% while the true error is '
          f'{sub_false[acc].mean() / max(t_is_false[base].mean(), 1e-9):.1f}x the baseline.')
    # WHY, in counting terms. TDC reads the RATIO of decoys to targets ABOVE a score. Selecting
    # targets by q keeps ~every target above the cut but only a pairing-determined sample of the
    # decoys above it. Overall the subset is still 1:1 (one decoy per kept target) - which is
    # exactly why "we kept the paired decoys, so it is symmetric" is wrong: the symmetry that
    # matters is above the threshold, not in total.
    s_gate = t_scores[gate].min() if gate.any() else np.inf
    tf, df = int((t_scores >= s_gate).sum()), int((d_scores >= s_gate).sum())
    ts, ds = int((t_scores[gate] >= s_gate).sum()), int((d_scores[gate] >= s_gate).sum())
    print(f'\n  counting view at the gate score cut ({s_gate:.2f}):')
    print(f'    full population : {tf:>7,} targets, {df:>6,} decoys above the cut  '
          f'-> ratio {df / max(tf, 1):.4f}')
    print(f'    retained subset : {ts:>7,} targets, {ds:>6,} decoys above the cut  '
          f'-> ratio {ds / max(ts, 1):.4f}')
    print(f'    targets above the cut retained {100 * ts / max(tf, 1):5.1f}%, '
          f'decoys above the cut retained {100 * ds / max(df, 1):5.1f}%  '
          f'<- the asymmetry, with NO model retraining involved')
    print(f'    (subset is 1:1 overall: {int(gate.sum()):,} targets and {int(gate.sum()):,} decoys)')

    s1 = t_scores[base].min() if base.any() else np.inf
    print(f'  -> null support at the baseline 1% score cut ({s1:.2f}): '
          f'{int((d_scores >= s1).sum()):,} decoys against {int((t_scores >= s1).sum()):,} targets '
          f'in the full competition, but only {int((d_scores[gate] >= s1).sum()):,} against '
          f'{int((t_scores[gate] >= s1).sum()):,} inside the gated subset')
    print('     The decoys were not selected; the targets were. That is the whole effect - and in '
          'a real\n     competition it is stronger still, since a target clears the gate partly by '
          'beating its own decoy.')


if __name__ == '__main__':
    raise SystemExit(main())
