#!/usr/bin/env python3
"""How much of the mean(best-N) result survives a de-contaminated entrapment oracle?

Rebuilds each arm's pass-1 FDP curve from the per-entry `experiment_precursor_qvalue` in the
sidecars, twice: once with the full entrapment set (what Osprey reported), and once with
near-copy entrapment removed and `r` recomputed. Then re-derives the two headline metrics and the
gain vs the max arm.

WHY THIS IS A BRACKET, NOT A TRUTH. Removing near-copies is a NON-random subsample of the
entrapment population, so the filtered estimator is not guaranteed unbiased - it models only the
dissimilar false peptides. The other machine's foreign-species (Arabidopsis) result indicates the
SURVIVING shuffles are still somewhat over-identified, so the filtered number remains an
over-estimate of true FDP, just a smaller one. Read the pair as bounds:

    full entrapment      -> upper bound on FDP  (conservative, what we reported)
    near-copies removed  -> lower bound on the correction

What makes the arithmetic defensible is the other machine's ratio sweep: combined FDP is
ratio-invariant across a 10x change in pool size once `r` is factored in
(`ai/docs/osprey-library-generation-guide.md`).

    python contamination_corrected.py
"""
import bisect
import csv
import glob
import json
import os
import sys

MANIFEST = r'D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment\osprey_library_db_pairing.tsv'
R_FULL = 0.9699          # entrapment:target DB ratio as Osprey reported it
LIB_GATE_FRAC = None     # set from libwide_gate.txt; fraction of LIBRARY entrapment gated out
Q_REPORTED = 0.01
FDP_MATCH = 0.01

AA = dict(zip("GASPVTCLINDQKEMHFRYW",
              [57.02146, 71.03711, 87.03203, 97.05276, 99.06841, 101.04768, 103.00919,
               113.08406, 113.08406, 114.04293, 115.02694, 128.05858, 128.09496, 129.04259,
               131.04049, 137.05891, 147.06841, 156.10111, 163.06333, 186.07931]))
H2O, PROT = 18.010565, 1.007276


def ladder(p):
    b, s = [], 0.0
    for ch in p[:-1]:
        s += AA.get(ch, 0.0); b.append(s + PROT)
    y, s = [], 0.0
    for ch in reversed(p[1:]):
        s += AA.get(ch, 0.0); y.append(s + H2O + PROT)
    return sorted(b + y)


def overlap(a, t, tol=0.02):
    la, lt = ladder(a), ladder(t)
    if not la:
        return 0.0
    m = 0
    for x in la:
        i = bisect.bisect_left(lt, x - tol)
        if i < len(lt) and lt[i] <= x + tol:
            m += 1
    return m / len(la)


def curve(pairs, r):
    """(discoveries at reported q, its FDP, discoveries at matched 1% true FDP).

    pairs: list of (q, is_entrapment). combined FDP = n_p*(1+1/r)/(n_t+n_p), the estimator the
    other machine's ratio sweep uses and the one Osprey's `Combined` column reports.
    """
    pairs.sort(key=lambda x: x[0])
    nt = npx = 0
    disc_q = fdp_q = None
    best_matched = 0
    for q, is_ent in pairs:
        if is_ent:
            npx += 1
        else:
            nt += 1
        tot = nt + npx
        if tot == 0:
            continue
        fdp = npx * (1.0 + 1.0 / r) / tot
        if q <= Q_REPORTED:
            disc_q, fdp_q = nt, fdp
        if fdp <= FDP_MATCH and nt > best_matched:
            best_matched = nt
    return disc_q, fdp_q, best_matched


def main():
    global LIB_GATE_FRAC
    if os.path.exists('libwide_gate.txt'):
        for line in open('libwide_gate.txt'):
            if 'overlap > 0.40' in line:
                LIB_GATE_FRAC = float(line.split('(')[1].split('%')[0]) / 100.0
    if LIB_GATE_FRAC is None:
        print('libwide_gate.txt missing/incomplete; run the library-wide estimate first',
              file=sys.stderr)
        return
    r_filt = R_FULL * (1.0 - LIB_GATE_FRAC)
    print(f'library-wide overlap-gate rejection {LIB_GATE_FRAC*100:.2f}%  ->  '
          f'r {R_FULL:.4f} -> {r_filt:.4f}\n')

    arms = {}
    for path in sorted(glob.glob('arm_*.json')):
        tag = os.path.basename(path)[4:-5].replace('_', '-')
        arms[tag] = json.load(open(path))
    if not arms:
        print('no arm_*.json yet', file=sys.stderr)
        return

    # Near-copy classification is a LIBRARY property, so classify once over the union of every
    # arm's accepted entrapment rather than per arm.
    ent_seq = {}
    for d in arms.values():
        for k, v in d['info'].items():
            if '_p_target' in (v[1] or ''):
                ent_seq[v[0]] = None
    pidx, tseq = {}, {}
    with open(MANIFEST, newline='', encoding='utf-8') as fh:
        for row in csv.DictReader(fh, delimiter='\t'):
            t, s, k = row['peptide_type'], row['sequence'], row['peptide_pair_index']
            if t == 'p_target' and s in ent_seq:
                pidx[s] = k
            elif t == 'target':
                tseq[k] = s
    near = set()
    for s in ent_seq:
        t = tseq.get(pidx.get(s, ''))
        if t and overlap(s, t) > 0.40:
            near.add(s)
    print(f'accepted entrapment sequences across all arms: {len(ent_seq):,}   '
          f'gated as near-copy: {len(near):,} ({len(near)/max(len(ent_seq),1)*100:.1f}%)\n')

    hdr = (f"{'arm':<14}{'disc@1%q':>10}{'FDP%':>8}{'matched':>9}{'gain%':>8}   "
           f"{'| disc@1%q':>11}{'FDP%':>8}{'matched':>9}{'gain%':>8}")
    print(f"{'':14}{'--- as reported (full entrapment) ---':^35}   {'--- near-copies removed ---':^36}")
    print(hdr)
    print('-' * len(hdr))
    base_full = base_filt = None
    rows = []
    for tag in sorted(arms, key=lambda t: 1 if t == 'max' else int(t.rsplit('-', 1)[1])):
        d = arms[tag]
        full, filt = [], []
        for k, v in d['info'].items():
            seq, pro, q = v
            is_ent = '_p_target' in (pro or '')
            if 'decoy' in (pro or '').lower():
                continue
            full.append((q, is_ent))
            if not (is_ent and seq in near):
                filt.append((q, is_ent))
        a = curve(full, R_FULL)
        b = curve(filt, r_filt)
        if tag == 'max':
            base_full, base_filt = a[2], b[2]
        ga = (a[2] / base_full - 1) * 100 if base_full else 0.0
        gb = (b[2] / base_filt - 1) * 100 if base_filt else 0.0
        rows.append((tag, a, ga, b, gb))
        print(f"{tag:<14}{a[0] or 0:>10,}{(a[1] or 0)*100:>8.3f}{a[2]:>9,}{ga:>+8.2f}   "
              f"{b[0] or 0:>11,}{(b[1] or 0)*100:>8.3f}{b[2]:>9,}{gb:>+8.2f}")
    print()
    for tag, a, ga, b, gb in rows:
        if tag == 'max':
            continue
        print(f"  {tag:<14} gain {ga:+.2f}%  ->  {gb:+.2f}%   (shift {gb-ga:+.2f} pts)")
    json.dump([{'arm': t, 'full': a, 'gain_full': ga, 'filt': b, 'gain_filt': gb}
               for t, a, ga, b, gb in rows], open('contamination_corrected.json', 'w'))


if __name__ == '__main__':
    main()
