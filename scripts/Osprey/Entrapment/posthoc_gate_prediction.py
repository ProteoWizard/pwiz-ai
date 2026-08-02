#!/usr/bin/env python3
"""Post-hoc gate correction on ONE arm, as a cohort-matched prediction for a gated library.

The existing -22% correction (0.894% -> 0.695%) was measured on the 163-file TDP-43 run. This
runs the same surgery on whatever arm you point it at, so a 40-file `ungated` run yields a
prediction on the SAME cohort the directly-searched `gated` arm measures. That removes cohort
size as an explanation for any difference between the two.

WHY THE TWO ARE NOT THE SAME EXPERIMENT, which is the point of running both:

    post-hoc removal   near-copies compete for spectra, then are DELETED from the oracle.
                       Entrapment pool shrinks; r must be rescaled by (1 - gate fraction).
    gated library      near-copies are REPLACED by dissimilar shuffles at build time and
                       never compete at all. Pool size is preserved; r is unchanged.

If the combined estimator is ratio-invariant (the library-generation guide's 10x ratio sweep
says it is) the two should agree. A gap localises to the COMPETITION effect -- near-copies
absorbing spectra from their own targets -- which only a gated library can remove and which
post-hoc oracle surgery structurally cannot see.

    python posthoc_gate_prediction.py <arm.json> <pairing.tsv> --r 0.9699 --gate-frac 0.040355
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from contamination_corrected import curve, overlap          # noqa: E402


def classify_near(arm, manifest, thresh=0.40):
    """Entrapment sequences in this arm's accepted set whose overlap with their OWN paired
    target exceeds the gate threshold. Pairing comes from the manifest's peptide_pair_index,
    the same key the library build uses."""
    ent_seq = {v[0] for v in arm['info'].values() if '_p_target' in (v[1] or '')}
    pidx, tseq = {}, {}
    with open(manifest, 'r', encoding='utf-8', errors='replace') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {n: i for i, n in enumerate(header)}
        i_seq, i_type, i_pair = col['sequence'], col['peptide_type'], col['peptide_pair_index']
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) <= i_pair:
                continue
            if p[i_type] == 'p_target' and p[i_seq] in ent_seq:
                pidx[p[i_seq]] = p[i_pair]
            elif p[i_type] == 'target':
                tseq[p[i_pair]] = p[i_seq]
    near = set()
    for s in ent_seq:
        t = tseq.get(pidx.get(s, ''))
        if t and overlap(s, t) > thresh:
            near.add(s)
    return ent_seq, near


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('arm')
    ap.add_argument('manifest')
    ap.add_argument('--r', type=float, required=True,
                    help="the arm's REPORTED entrapmentRatio, not the library's DB ratio")
    ap.add_argument('--gate-frac', type=float, required=True,
                    help='library-wide rejectable entrapment fraction, e.g. 0.040355')
    ap.add_argument('--label', default='')
    a = ap.parse_args()

    arm = json.load(open(a.arm))
    ent_seq, near = classify_near(arm, a.manifest)
    print(f'{a.label or os.path.basename(a.arm)}')
    print(f'  accepted entrapment sequences {len(ent_seq):,}   '
          f'near-copies {len(near):,} ({len(near)/max(len(ent_seq),1)*100:.1f}% of ACCEPTED)')
    print(f'  library-wide rejectable fraction {a.gate_frac*100:.4f}%  ->  '
          f'enrichment among accepted {len(near)/max(len(ent_seq),1)/a.gate_frac:.1f}x')

    full, filt = [], []
    for seq, pro, q in arm['info'].values():
        if 'decoy' in (pro or '').lower():
            continue
        is_ent = '_p_target' in (pro or '')
        full.append((q, is_ent))
        if not (is_ent and seq in near):
            filt.append((q, is_ent))

    r_filt = a.r * (1.0 - a.gate_frac)
    d_full, f_full, m_full = curve(full, a.r)
    d_filt, f_filt, m_filt = curve(filt, r_filt)

    print(f'\n  {"":22}{"disc@1%q":>10}{"trueFDP%":>10}{"matched@1%":>12}')
    print(f'  {"as reported (full)":22}{d_full or 0:>10,}{(f_full or 0)*100:>10.3f}{m_full:>12,}')
    print(f'  {"near-copies removed":22}{d_filt or 0:>10,}{(f_filt or 0)*100:>10.3f}{m_filt:>12,}')
    if f_full and f_filt:
        rel = (f_filt - f_full) / f_full * 100.0
        print(f'\n  POST-HOC PREDICTION for a gated library on this cohort: '
              f'FDP {f_full*100:.3f}% -> {f_filt*100:.3f}%  ({rel:+.1f}% relative)')
        print('  Compare against the DIRECTLY MEASURED gated arm. Agreement validates the '
              'estimator;\n  a gap is the competition effect post-hoc surgery cannot see.')
    json.dump({'label': a.label, 'r': a.r, 'r_filt': r_filt,
               'nAcceptedEntrapment': len(ent_seq), 'nNearCopy': len(near),
               'full': {'disc': d_full, 'fdp': f_full, 'matched': m_full},
               'filt': {'disc': d_filt, 'fdp': f_filt, 'matched': m_filt}},
              open(os.path.join(os.path.dirname(os.path.abspath(a.arm)),
                                'posthoc.' + os.path.basename(a.arm)), 'w'), indent=1)


if __name__ == '__main__':
    main()
