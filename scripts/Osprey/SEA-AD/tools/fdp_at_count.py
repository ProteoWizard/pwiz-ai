#!/usr/bin/env python3
"""Localize the pass-2 FDP inflation: plot true combined entrapment FDP against ACCEPTED TARGET COUNT
(not q), overlaying pass-1 (from the report fdpView) and pass-2 (from fdrbench.tsv) on the same x-axis.
If pass-2 tracks pass-1 up to pass-1's count and only diverges beyond it, the inflation is the ADDED
(reconciliation/gap-fill) IDs, not a mis-ranking of the shared core.

Usage: python fdp_at_count.py <run_dir> [<run_dir> ...]
"""
import sys, os, re, json


def entrap_set(pairing_path):
    ent = set()
    nT = nE = 0
    with open(pairing_path, encoding='utf-8') as f:
        h = f.readline().rstrip('\n').split('\t')
        si, ti = h.index('sequence'), h.index('peptide_type')
        for line in f:
            p = line.rstrip('\n').split('\t')
            if len(p) <= ti:
                continue
            if p[ti] == 'p_target':
                ent.add(p[si]); nE += 1
            elif p[ti] == 'target':
                nT += 1
    return ent, nT, nE


def pass1_fdp_by_count(html_path):
    """Return (counts[], fdp[]) for pass-1 experiment view: FDP as a function of nTargetAccepted."""
    t = open(html_path, encoding='utf-8').read()
    d = json.loads(re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', t, re.S).group(1))
    for v in d.get('fdpViews', []):
        if v.get('pass') == 1 and v.get('scope') == 'experiment':
            return v.get('nTargetAccepted') or [], v.get('combined') or []
    return [], []


def interp(xs, ys, x0):
    if not xs:
        return float('nan')
    if x0 <= xs[0]:
        return ys[0]
    for i in range(1, len(xs)):
        if xs[i] >= x0:
            x1, x2, y1, y2 = xs[i-1], xs[i], ys[i-1], ys[i]
            return y2 if x2 == x1 else y1 + (y2-y1)*(x0-x1)/(x2-x1)
    return ys[-1]


def analyze(run_dir):
    fb = os.path.join(run_dir, 'fdrbench.tsv')
    pr = os.path.join(run_dir, 'fdrbench.tsv.pairing.tsv')
    html = os.path.join(run_dir, 'out.model-diagnostics.html')
    ent, nT_lib, nE_lib = entrap_set(pr)
    r = nE_lib / nT_lib
    rows = []
    with open(fb, encoding='utf-8') as f:
        h = f.readline().rstrip('\n').split('\t')
        pi, qi = h.index('peptide'), h.index('q_value')
        for line in f:
            p = line.rstrip('\n').split('\t')
            rows.append((float(p[qi]), p[pi] in ent))
    rows.sort(key=lambda x: x[0])            # ascending q = best first
    # cumulative FDP as targets accumulate
    p1c, p1f = pass1_fdp_by_count(html) if os.path.exists(html) else ([], [])
    name = os.path.basename(run_dir.rstrip('/\\'))
    print(f"\n=== {name}  (r={r:.4f}) ===")
    print(f"  {'N_T':>7} {'pass2 N_E':>10} {'pass2 FDP':>10} {'pass1 FDP@sameN':>16}")
    checkpoints = [20000, 30000, 40000, 45016, 50000, 55555, 60000, 60844]
    nt = ne = 0
    ci = 0
    for q, isE in rows:
        if isE:
            ne += 1
        else:
            nt += 1
        while ci < len(checkpoints) and nt == checkpoints[ci] and not isE:
            tot = nt + ne
            comb = (1 + 1/r) * ne / tot
            p1 = interp(p1c, p1f, nt) * 100 if p1c else float('nan')
            print(f"  {nt:>7,} {ne:>10,} {comb*100:>9.3f}% {p1:>15.3f}%")
            ci += 1
        if ci >= len(checkpoints):
            break


if __name__ == '__main__':
    for d in sys.argv[1:]:
        analyze(d)
