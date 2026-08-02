#!/usr/bin/env python3
"""How much of an arm's measured FDP is I/L-isobaric entrapment that is really PRESENT?

Leucine and isoleucine have identical residue masses (113.08406), so an entrapment peptide that
differs from a human target only by I<->L substitutions is mass-identical AND produces an
identical fragment ladder. It is indistinguishable from that target by mass spectrometry, so it
is not a model of a false discovery at all - it will be detected wherever its human twin is, and
every such detection is counted as false when it is not.

Exact-sequence collision audits miss this entirely (they compare strings), which is why the
2026-08-02 series initially reported 0 collisions in all three libraries. Under I->L
normalisation the counts are 722 (ungated) / 667 (gated) / 1,012 (arabidopsis) - and the
enrichment in the foreign-species library is a candidate explanation for its much higher
measured FDP.

Recomputes the arm's FDP curve with those entrapment entries removed from the oracle. `r` is
rescaled by the LIBRARY-WIDE colliding fraction, matching how posthoc_gate_prediction.py handles
the near-copy gate.

    python il_collision_correction.py <arm.json> <pairing.tsv> --r 0.969 --label NAME
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from contamination_corrected import curve                    # noqa: E402


def il(s):
    return s.replace('I', 'L')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('arm')
    ap.add_argument('manifest')
    ap.add_argument('--r', type=float, required=True)
    ap.add_argument('--label', default='')
    a = ap.parse_args()

    targets, n_ent, n_coll = set(), 0, 0
    with open(a.manifest, 'r', encoding='utf-8', errors='replace') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {n: i for i, n in enumerate(header)}
        i_seq, i_type = col['sequence'], col['peptide_type']
        ent = []
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) <= i_type:
                continue
            if p[i_type] == 'target':
                targets.add(il(p[i_seq]))
            elif p[i_type] == 'p_target':
                ent.append(p[i_seq])
    colliding = {s for s in ent if il(s) in targets}
    n_ent, n_coll = len(set(ent)), len(colliding)
    frac = n_coll / max(n_ent, 1)

    arm = json.load(open(a.arm))
    full, filt = [], []
    acc_ent = acc_coll = 0
    for seq, pro, q in arm['info'].values():
        if 'decoy' in (pro or '').lower():
            continue
        is_ent = '_p_target' in (pro or '')
        if is_ent:
            acc_ent += 1
        hit = is_ent and seq in colliding
        if hit:
            acc_coll += 1
        full.append((q, is_ent))
        if not hit:
            filt.append((q, is_ent))

    print(f'{a.label or os.path.basename(a.arm)}')
    print(f'  library entrapment {n_ent:,}   I/L-colliding {n_coll:,} ({frac*100:.4f}%)')
    print(f'  ACCEPTED entrapment {acc_ent:,}   of which I/L-colliding {acc_coll:,} '
          f'({acc_coll/max(acc_ent,1)*100:.2f}%)   '
          f'enrichment vs library {(acc_coll/max(acc_ent,1))/max(frac,1e-12):.1f}x')

    d0, f0, m0 = curve(full, a.r)
    d1, f1, m1 = curve(filt, a.r * (1.0 - frac))
    print(f'\n  {"":24}{"disc@1%q":>10}{"trueFDP%":>10}{"matched@1%":>12}')
    print(f'  {"as reported":24}{d0 or 0:>10,}{(f0 or 0)*100:>10.3f}{m0:>12,}')
    print(f'  {"I/L collisions removed":24}{d1 or 0:>10,}{(f1 or 0)*100:>10.3f}{m1:>12,}')
    if f0 and f1:
        print(f'\n  FDP {f0*100:.3f}% -> {f1*100:.3f}%  ({(f1-f0)/f0*100:+.1f}% relative)')


if __name__ == '__main__':
    main()
