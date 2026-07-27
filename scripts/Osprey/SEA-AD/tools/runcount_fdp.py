#!/usr/bin/env python3
"""True entrapment FDP by number-of-runs-identified, from an Osprey --model-diagnostics report's
crossRun block (runCountHistogram / entrapmentRunCountHistogram). Shows the tail Kall flags: FDP
concentrates in low-run-count peptides; ">= half the runs" is strong FDR control. Combined
ratio-corrected estimator (1+1/r)*E/(T+E).

Usage: python runcount_fdp.py <run_dir_or_html> [r=0.9695]
"""
import sys, os, re, json


def load(arg):
    if not arg.lower().endswith('.html'):
        for name in ('out.model-diagnostics.html', 'seaad.model-diagnostics.html', 'caldiag.model-diagnostics.html'):
            p = os.path.join(arg.rstrip('/\\'), name)
            if os.path.exists(p):
                arg = p
                break
    t = open(arg, encoding='utf-8').read()
    return json.loads(re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', t, re.S).group(1)), arg


def main():
    d, path = load(sys.argv[1])
    r = float(sys.argv[2]) if len(sys.argv) > 2 else 0.9695
    print(f"# {os.path.basename(os.path.dirname(path))}  r={r}")
    for scope in ('experiment', 'perRun'):
        cr = d['crossRun'][scope]
        T, E = cr['runCountHistogram'], cr['entrapmentRunCountHistogram']
        n = len(T)
        print(f"\n=== {scope} ===  atLeastHalf={cr['atLeastHalf']:,}  meanPerRun={cr['meanPerRun']:.0f}")
        print(f"  {'#runs':>6} {'nPept':>9} {'nEntrap':>8} {'FDP_exact':>10} | {'cum>=k nPept':>12} {'cum>=k FDP':>11}")
        for k in range(1, n + 1):
            i = k - 1
            fe = (1 + 1 / r) * E[i] / (T[i] + E[i]) if (T[i] + E[i]) else 0.0
            cT, cE = sum(T[i:]), sum(E[i:])
            cf = (1 + 1 / r) * cE / (cT + cE) if (cT + cE) else 0.0
            print(f"  {k:>6} {T[i]:>9,} {E[i]:>8,} {fe*100:>9.2f}% | {cT:>12,} {cf*100:>10.2f}%")
        h = (n + 1) // 2
        cT, cE = sum(T[h-1:]), sum(E[h-1:])
        cf = (1 + 1 / r) * cE / (cT + cE) if (cT + cE) else 0.0
        print(f"  >= half (>={h} runs): nPept={cT:,}  FDP={cf*100:.2f}%")


if __name__ == '__main__':
    main()
