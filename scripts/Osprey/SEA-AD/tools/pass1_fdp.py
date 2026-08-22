#!/usr/bin/env python3
"""Pass-1 entrapment FDP from a run's --model-diagnostics report.

A FirstPassFDR-only run writes no FDRBench TSV (that comes off the pass-2 path), so
fdp_at_count.py cannot read these runs. The mdiag report does carry fdpViews, each tagged with
the pass it came from, which is where pass-1 FDP lives.

This exists to answer one question about the training levers: a lever that RAISES the
identification count is only an improvement if the false-discovery proportion did not rise with
it. Counts alone cannot distinguish a better model from a looser one.

Usage: pass1_fdp.py <run_dir> [<run_dir> ...]
"""
import json
import os
import re
import sys


QCUT = 0.01
# Matched-FDP levels to report alongside the count at 1% nominal q. Counts at a NOMINAL q are
# not comparable across arms that land at different true FDP, because an arm can always report
# more by spending more error; the matched-FDP column is the comparison this project treats as
# the rigorous one. 0.0065 is the lowest of the three because it was the best FDP any 32-file
# arm reached while the training-sample levers were being explored.
MATCH_FDP = (0.0065, 0.0075, 0.01)


def fmt(x):
    return '%.4f%%' % (x * 100) if isinstance(x, (int, float)) else str(x)


def load(run):
    path = run if run.lower().endswith('.html') else os.path.join(run, 'out.model-diagnostics.html')
    if not os.path.exists(path):
        return None
    text = open(path, encoding='utf-8', errors='ignore').read()
    m = re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', text, re.S)
    return json.loads(m.group(1)) if m else None


def views(node, out):
    """fdpViews can sit at any depth depending on the report version, so walk for them."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == 'fdpViews' and isinstance(v, list):
                out.extend(v)
            else:
                views(v, out)
    elif isinstance(node, list):
        for v in node:
            views(v, out)
    return out


for run in sys.argv[1:]:
    data = load(run)
    print('=== %s' % os.path.basename(run.rstrip('\\/')))
    if data is None:
        print('   no model-diagnostics report')
        continue
    found = views(data, [])
    if not found:
        print('   report has no fdpViews; top-level keys: %s' % ', '.join(sorted(data)[:14]))
        continue
    for v in found:
        if not isinstance(v, dict):
            continue
        tag = v.get('pass', v.get('Pass', '?'))
        # These fields are CURVES over increasing q, not scalars: q[i] is the reported q-value
        # and combined[i] / paired[i] the entrapment FDP estimates at that point. Report the
        # last point at or below the 1% operating cutoff, which is where the counts are quoted.
        qs = v.get('q') or []
        if not isinstance(qs, list) or not qs:
            continue
        idx = max((i for i, q in enumerate(qs) if q <= QCUT), default=None)
        if idx is None:
            print('   pass=%s scope=%-11s (curve starts above q=%g)' % (tag, v.get('scope', '?'), QCUT))
            continue
        get = lambda k: (v.get(k) or [None] * len(qs))[idx]
        print('   pass=%s scope=%-11s q=%.4f n=%-9s combinedFDP=%-9s pairedFDP=%s' %
              (tag, v.get('scope', '?'), qs[idx], get('nTargetAccepted'),
               fmt(get('combined')), fmt(get('paired'))))
        # Counts at a nominal q are not comparable between arms that land at different true
        # FDP - an arm can buy discoveries with error. Report the count at a MATCHED true FDP
        # as well, which is the comparison this project treats as the rigorous one.
        fdps, ns = v.get('combined') or [], v.get('nTargetAccepted') or []
        for target in MATCH_FDP:
            best = None
            for i, f in enumerate(fdps):
                if isinstance(f, (int, float)) and f <= target and i < len(ns):
                    best = ns[i]
            if best is not None:
                print('              at true FDP <= %.3f%%: n=%s' % (target * 100, best))
