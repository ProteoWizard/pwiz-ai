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
REDUCE = re.compile(r'peak co-assignment: reducing the experiment boundary over')
JOIN = re.compile(r'Peak co-assignment: joining apex RT over (\d+) file')
MEM = re.compile(r'^\[[\d/]+ [\d:]+\]\t(\d+)\t(\d+)\t')
STAMP = re.compile(r'^\[(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\]')
PAYLOAD = re.compile(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', re.S)

MIN_LOG_BYTES = 10000


def split_seconds(seg):
    """Wall seconds in the panel's two halves, from the log's own timestamps.

    Phase 1 streams every record of every 1st-pass sidecar to find the decoy
    acceptance boundaries. Phase 2 re-reads two columns of every .scores.parquet
    and joins them against those sidecars. Which half dominates decides where a
    latency fix would have to go, and the split is not obvious from the total.

    Returns (scan_s, join_s) or (None, None) when the log predates the markers.
    """
    from datetime import datetime

    def stamp(line):
        m = STAMP.match(line)
        return datetime.strptime(m.group(1), '%Y/%m/%d %H:%M:%S') if m else None

    t0 = t_reduce = t_join = None
    for line in seg:
        if t0 is None and SCAN.search(line):
            t0 = stamp(line)
        elif t_reduce is None and REDUCE.search(line):
            t_reduce = stamp(line)
        elif t_join is None and JOIN.search(line):
            t_join = stamp(line)
    t_end = stamp(seg[-1]) if seg else None
    if not (t0 and t_reduce and t_join and t_end):
        return None, None
    return (t_reduce - t0).total_seconds(), (t_end - t_join).total_seconds()


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
                seg = lines[lo:i + 1]
                mem = [(int(x.group(1)), int(x.group(2)))
                       for x in (MEM.match(s) for s in seg) if x]
                out.append({
                    'pass': int(m.group(1)),
                    'rows': int(m.group(2).replace(',', '')),
                    'files': int(m.group(3)),
                    'secs': float(m.group(4)),
                    'mem': mem,
                    'split': split_seconds(seg),
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
    print('%5s %4s %12s %9s %8s %8s %6s %10s  %10s  %s' % (
        'files', 'pass', 'rows', 'secs', 'scan_s', 'join_s', 'join%', 'rows/file',
        'priv max', 'log'))
    for r in recs:
        pv = max((m[1] for m in r['mem']), default=0) / 1024.0
        scan_s, join_s = r.get('split', (None, None))
        if scan_s is None:
            span, pct = '       -        -', '     -'
        else:
            span = '%8.1f %8.1f' % (scan_s, join_s)
            tot = scan_s + join_s
            pct = '%5.0f%%' % (100.0 * join_s / tot) if tot > 0 else '     -'
        print('%5d %4d %12d %9.1f %s %s %10.0f  %7.2f GB  %s' % (
            r['files'], r['pass'], r['rows'], r['secs'], span, pct,
            r['rows'] / float(r['files']), pv, r['log']))
    print('\nscan_s is phase 1 (stream every 1st-pass sidecar record for the acceptance')
    print('boundaries); join_s is phase 2 (re-read two columns of every .scores.parquet and')
    print('join them). priv max is NOT attributable to the panel - use the delta view.')


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
