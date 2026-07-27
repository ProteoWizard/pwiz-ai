#!/usr/bin/env python3
"""Compute entrapment FDP at reported q from an Osprey --fdrbench pass-2 output.

The current build's --model-diagnostics report only emits pass-1 fdpViews (the pass-2
FDP view was dropped at commit 2985b4d063 / #4410), so the pass-2 entrapment FDP -- the
metric that actually distinguishes OSPREY_PASS2_QVALUE=percolator from =transfer -- must
be computed directly from the pass-2 FDRBench input Osprey writes at the merge node.

Reads <dir>/fdrbench.tsv (reported precursors: peptide,mod_peptide,charge,q_value,score,protein)
and <dir>/fdrbench.tsv.pairing.tsv (sequence -> peptide_type: target|p_target), and reports the
ratio-corrected combined FDP = (1+1/r)*N_E/(N_T+N_E) and lower bound = N_E/(r*(N_T+N_E)) over a
q-sweep. This is the same 'combined' estimator the report's pass-1 fdpView uses
(docs/fractional-entrapment.md), so pass-1 (from the HTML) and pass-2 (from here) are comparable.

Usage: python compute_pass2_fdp.py <run_dir> [<run_dir> ...]
"""
import sys, os


def load_pairing(path):
    seqtype = {}
    nT = nE = 0
    with open(path, encoding='utf-8') as f:
        header = f.readline().rstrip('\n').split('\t')
        seq_i = header.index('sequence')
        typ_i = header.index('peptide_type')
        for line in f:
            p = line.rstrip('\n').split('\t')
            if len(p) <= typ_i:
                continue
            t = p[typ_i]
            seqtype[p[seq_i]] = t
            if t == 'p_target':
                nE += 1
            elif t == 'target':
                nT += 1
    return seqtype, nT, nE


def analyze(run_dir, qs=(0.001, 0.005, 0.01, 0.02, 0.05)):
    fb = os.path.join(run_dir, 'fdrbench.tsv')
    pr = os.path.join(run_dir, 'fdrbench.tsv.pairing.tsv')
    if not (os.path.exists(fb) and os.path.exists(pr)):
        print(f"\n=== {run_dir} ===\n  MISSING fdrbench.tsv or pairing.tsv")
        return
    seqtype, nT_lib, nE_lib = load_pairing(pr)
    r = nE_lib / nT_lib
    rows = []          # (q, cls)  cls in {'target','p_target',None}
    with open(fb, encoding='utf-8') as f:
        header = f.readline().rstrip('\n').split('\t')
        pep_i = header.index('peptide')
        q_i = header.index('q_value')
        for line in f:
            p = line.rstrip('\n').split('\t')
            rows.append((float(p[q_i]), seqtype.get(p[pep_i])))
    rows.sort(key=lambda x: x[0])
    nU = sum(1 for _, c in rows if c is None)
    name = os.path.basename(run_dir.rstrip('/\\'))
    print(f"\n=== {name} ===")
    print(f"  library r=|E|/|T|={r:.4f} ({nE_lib:,} p_target / {nT_lib:,} target)")
    print(f"  reported precursors={len(rows):,} (unclassified={nU:,}); qmax={rows[-1][0]:.4f}")
    print(f"  {'q<=':>7} {'N_T':>9} {'N_E':>7} {'combinedFDP':>12} {'lowerFDP':>10}")
    for qc in qs:
        nt = ne = 0
        for q, cls in rows:
            if q > qc:
                break
            if cls == 'p_target':
                ne += 1
            elif cls == 'target':
                nt += 1
        tot = nt + ne
        comb = (1 + 1 / r) * ne / tot if tot else float('nan')
        low = ne / (r * tot) if tot else float('nan')
        print(f"  {qc:>7.3f} {nt:>9,} {ne:>7,} {comb*100:>11.3f}% {low*100:>9.3f}%")


if __name__ == '__main__':
    for d in sys.argv[1:]:
        analyze(d)
