#!/usr/bin/env python3
"""Memory SHAPE within each pipeline phase, from a run.log's --memstamp columns.

Answers "is this phase flat iteration, or does it ramp into a join at the end?" - the
question #4600 (moving PerFileRescoring's whole-run join into SecondPassFDR's pull) is
supposed to change. A fan-out phase should be flat; only a join phase should ramp.

Usage: phase_mem_shape.py <run.log> [<run.log> ...]
"""
import re
import sys

LINE = re.compile(r'^\[(\d{4}/\d\d/\d\d) (\d\d):(\d\d):(\d\d)\]\t(\d+)\t(\d+)\t(.*)$')
TASK = re.compile(r'\[TASK\] (\w+):(starting|done)')


def phases(path):
    """Returns {phase: (points, completed)}. completed is False for a phase whose
    :done line never appeared - its last decile is just 'the most recent slice of an
    unfinished stage', which is NOT the end-of-phase join the shape verdict is about."""
    cur, out, day0 = None, {}, None
    for raw in open(path, encoding='utf-8', errors='ignore'):
        m = LINE.match(raw.rstrip('\n'))
        if not m:
            continue
        d, hh, mm, ss, managed, total, msg = m.groups()
        if day0 is None:
            day0 = d
        s = int(hh) * 3600 + int(mm) * 60 + int(ss) + (86400 if d != day0 else 0)
        t = TASK.search(msg)
        if t:
            if t.group(2) == 'starting':
                cur = t.group(1)
                out.setdefault(cur, [[], False])
            else:
                if t.group(1) in out:
                    out[t.group(1)][1] = True
                cur = None
            continue
        if cur and int(total) > 0:
            out[cur][0].append((s, int(managed), int(total)))
    return out


for path in sys.argv[1:]:
    print('=== %s' % path.split('/')[-1].split('\\')[-1])
    for name, (pts, done) in phases(path).items():
        if len(pts) < 20:
            continue
        t0, t1 = pts[0][0], pts[-1][0]
        span = max(t1 - t0, 1)
        print('  %-18s wall %4d min  n=%d' % (name, span / 60, len(pts)))
        rows = []
        for d in range(10):
            lo, hi = t0 + span * d / 10.0, t0 + span * (d + 1) / 10.0
            sel = [p for p in pts if lo <= p[0] <= hi]
            if not sel:
                continue
            rows.append((d, sum(p[2] for p in sel) / len(sel) / 1024.0,
                         max(p[2] for p in sel) / 1024.0))
        for d, mean, mx in rows:
            bar = '#' * int(mx / 2)
            print('     %3d-%3d%%  mean %5.1f GB  max %5.1f GB  %s' %
                  (d * 10, (d + 1) * 10, mean, mx, bar))
        # The shape verdict: last decile against the median of the first eight. Refused on a
        # phase still running: the baseline's PerFileRescoring was flat for its first 90% too,
        # so a partial log's last decile says nothing about the end-of-phase join.
        if not done:
            print('     -> phase still RUNNING; no shape verdict (the join, if any, is at the end)')
        elif len(rows) >= 9:
            base = sorted(r[2] for r in rows[:8])[4]
            end = rows[-1][2]
            print('     -> end/mid peak ratio %.2fx  (%s)' %
                  (end / base, 'RAMPS INTO A JOIN' if end / base > 1.5 else 'flat iteration'))
