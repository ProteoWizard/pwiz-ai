"""How the model-diagnostics peak co-assignment panel scales with the run count.

Every Osprey run log is already a memory trace of this phase. The panel logs its
own completion:

    [MODEL-DIAGNOSTICS] peak co-assignment (pass P): R detected rows over N file(s) in Ts

and under `--timestamp --memstamp` every line is prefixed with managed and
private MB. Every `out.model-diagnostics.html` additionally publishes the
populations the panel's cross-run maps ended up holding. So a scaling ladder over
the run sizes already on disk can be recovered after the fact, instead of being
bought with a night of instrumented runs.

Three views, because they answer three different questions and the first two are
easy to confuse:

  scaling   per-phase wall time and the memory MAXIMA inside the phase window.
            Read the time column; do NOT attribute the maxima to the panel (see
            below).
  delta     the memory RISE across the phase, and the managed floor under it.
            This is the view that says what the panel itself costs.
  retained  the cross-run populations the accumulators actually kept, read from
            the reports. This is what an O(runs) retention term would show up in.

**Maxima are not attributable; deltas are.** In a full-pipeline run the process
already holds the library and the whole first-pass state when this phase opens,
so the in-phase maximum mostly measures that floor. Ranking runs by maximum
produces a table where 86 files outrank 446. Only the rise across the phase, and
the managed value at a GC trough inside it, say anything about the panel.

Usage:
    python Measure-CoAssignmentScaling.py scaling  [root] [--filter SUBSTR]
    python Measure-CoAssignmentScaling.py delta    [root] [--filter SUBSTR]
    python Measure-CoAssignmentScaling.py retained [root] [--filter SUBSTR]

`root` defaults to D:\\test\\osprey-runs.
"""
import argparse
import json
import os
import re
import sys

DONE = re.compile(
    r'peak co-assignment \(pass (\d)\): ([\d,]+) detected rows over (\d+) file\(s\) in ([\d.]+)s')
SCAN = re.compile(r'Peak co-assignment: scanning 1st-pass sidecars over (\d+) file')
MEM = re.compile(r'^\[[\d/]+ [\d:]+\]\t(\d+)\t(\d+)\t')
PAYLOAD = re.compile(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', re.S)

MIN_LOG_BYTES = 10000


def phases_in_log(path):
    """Every co-assignment phase in one log, with its memstamp samples."""
    out, start, lines = [], None, []
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            lines.append(line)
            i = len(lines) - 1
            if SCAN.search(line) and start is None:
                start = i
            m = DONE.search(line)
            if m:
                # No scan marker means an older build that did not report phase 1;
                # fall back to a window generous enough to cover it.
                lo = start if start is not None else max(0, i - 3000)
                mem = [(int(x.group(1)), int(x.group(2)))
                       for x in (MEM.match(s) for s in lines[lo:i + 1]) if x]
                out.append({
                    'pass': int(m.group(1)),
                    'rows': int(m.group(2).replace(',', '')),
                    'files': int(m.group(3)),
                    'secs': float(m.group(4)),
                    'mem': mem,
                })
                start = None
    return out


def walk_files(root, suffix, filt):
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if not fn.endswith(suffix):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            if filt and filt not in rel:
                continue
            yield p, rel


def collect_logs(root, filt):
    recs = []
    for p, rel in walk_files(root, '.log', filt):
        try:
            if os.path.getsize(p) < MIN_LOG_BYTES:
                continue
            for r in phases_in_log(p):
                r['log'] = rel
                recs.append(r)
        except OSError:
            pass
    recs.sort(key=lambda r: (r['files'], r['pass'], r['rows']))
    return recs


def view_scaling(recs):
    print('%5s %4s %12s %9s %9s %10s  %10s %10s  %s' % (
        'files', 'pass', 'rows', 'secs', 'us/row', 'rows/file',
        'mgd max', 'priv max', 'log'))
    for r in recs:
        mg = max((m[0] for m in r['mem']), default=0) / 1024.0
        pv = max((m[1] for m in r['mem']), default=0) / 1024.0
        usrow = (r['secs'] * 1e6 / r['rows']) if r['rows'] else 0
        print('%5d %4d %12d %9.1f %9.2f %10.0f  %7.2f GB %7.2f GB  %s' % (
            r['files'], r['pass'], r['rows'], r['secs'], usrow,
            r['rows'] / float(r['files']), mg, pv, r['log']))


def view_delta(recs):
    print('%5s %11s %8s | %8s %8s %8s | %8s %8s %8s | %s' % (
        'files', 'rows', 'secs',
        'priv0', 'privMax', 'd_priv', 'mgd0', 'mgdMin', 'd_live', 'log'))
    for r in recs:
        if len(r['mem']) < 4:
            continue          # too few samples for a floor to mean anything
        mg = [m[0] / 1024.0 for m in r['mem']]
        pv = [m[1] / 1024.0 for m in r['mem']]
        print('%5d %11d %8.1f | %6.2fG %6.2fG %+7.2fG | %6.2fG %6.2fG %+7.2fG | %s' % (
            r['files'], r['rows'], r['secs'],
            pv[0], max(pv), max(pv) - pv[0],
            mg[0], min(mg), min(mg) - mg[0], r['log']))


def scope_population(scope):
    """Sum the per-class N of one co-assignment scope."""
    if not isinstance(scope, dict):
        return 0
    return sum(v['n'] for v in scope.values()
               if isinstance(v, dict) and isinstance(v.get('n'), int))


def view_retained(root, filt):
    rows = []
    for p, rel in walk_files(root, 'model-diagnostics.html', filt):
        try:
            with open(p, 'r', encoding='utf-8', errors='replace') as fh:
                m = PAYLOAD.search(fh.read())
            if not m:
                continue
            doc = json.loads(m.group(1).strip())
        except (OSError, ValueError):
            continue
        ca = doc.get('coAssignment') or {}
        rows.append((doc.get('fileCount') or 0,
                     scope_population(ca.get('run')),
                     scope_population(ca.get('experiment')), rel))
    rows.sort()
    print('%5s %12s %12s  %s' % ('files', 'run-scope N', 'exp-scope N', 'report'))
    for files, runN, expN, rel in rows:
        print('%5d %12d %12d  %s' % (files, runN, expN, rel))
    print('\nrun-scope N is one entry per DISTINCT detected precursor in the run-scope')
    print('accumulator, experiment-scope N the same for the pooled scope. These are the')
    print('populations CoAssignmentAccumulator._byPrecursor holds to the end of the build.')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('view', choices=('scaling', 'delta', 'retained'))
    ap.add_argument('root', nargs='?', default=r'D:\test\osprey-runs')
    ap.add_argument('--filter', help='only paths containing this substring')
    args = ap.parse_args()

    if args.view == 'retained':
        view_retained(args.root, args.filter)
        return 0
    recs = collect_logs(args.root, args.filter)
    if not recs:
        print('no peak co-assignment phases found under %s' % args.root)
        return 1
    (view_scaling if args.view == 'scaling' else view_delta)(recs)
    return 0


if __name__ == '__main__':
    sys.exit(main())
