#!/usr/bin/env python3
"""Summarize (and plot) an Osprey --timestamp --memstamp run log.

The console companion to perfviz.html. That page is for a human eye; this is for
answering the questions a gate actually asks, as NUMBERS:

  * what was the largest gap between log lines, and where
  * did the memory band DRIFT across the run, or return to the same floor
  * what was the peak

perfviz.html renders the same three series interactively. Use it to look; use this
to decide, to diff two runs, or to check a run from a terminal / an agent that
cannot open a browser.

Zero dependencies - stdlib only, like every other tool in this repo, so it runs on
a fresh machine with nothing installed. The numeric summary is stdlib-only, so it runs
anywhere; only --png needs matplotlib (pip install matplotlib).

REFUSES TO REPORT on a failed run unless --force. A log that died early still
produces a beautiful "0 gaps, flat memory" summary, which is worse than no summary
at all - that exact false pass happened during this tool's own development.

Log format (one line per emitted message):
    [yyyy/MM/dd HH:mm:ss]<TAB>managedMB<TAB>totalMB<TAB>message

Usage:
    python perfviz.py run.log
    python perfviz.py run.log --png run.png --gap-threshold 30
    python perfviz.py a.log b.log          # compare two runs
"""

import argparse
import datetime
import os
import re
import sys

LINE_RE = re.compile(
    r'^\[(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\]\t(\d+)\t(\d+)\t(.*)$')
FAIL_RE = re.compile(r'\[ERROR\]|Unhandled exception|Pipeline failed')


class Sample:
    __slots__ = ('t', 'managed', 'total', 'msg')

    def __init__(self, t, managed, total, msg):
        self.t = t
        self.managed = managed
        self.total = total
        self.msg = msg


def parse(path):
    """Return (samples, failed, nlines). Non-matching lines are ignored except
    for failure detection, so a stack trace still marks the run failed."""
    samples = []
    failed = False
    nlines = 0
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            nlines += 1
            if FAIL_RE.search(line):
                failed = True
            m = LINE_RE.match(line.rstrip('\n'))
            if not m:
                continue
            t = datetime.datetime.strptime(m.group(1), '%Y/%m/%d %H:%M:%S')
            samples.append(Sample(t, int(m.group(2)), int(m.group(3)), m.group(4)))
    return samples, failed, nlines


def gaps(samples, threshold):
    """Gaps >= threshold seconds, each with the line that PRECEDED the silence -
    that is the operation that was running, and the thing to add progress to."""
    out = []
    for i in range(1, len(samples)):
        d = (samples[i].t - samples[i - 1].t).total_seconds()
        if d >= threshold:
            out.append((d, samples[i - 1].t, samples[i - 1].msg))
    return out


def troughs(samples, key, buckets=12):
    """Per-bucket minima of a series - the floor the band returns to between
    cycles. Drift between the first and last bucket is the O(files) signal:
    a sawtooth whose FLOOR rises is accumulating; one that returns to the same
    floor is bounded, however tall its peaks.

    STARTUP IS EXCLUDED. Every run begins at ~0 and climbs while the process
    warms up (for Osprey, loading a multi-GB library). Including that makes the
    first floor ~0, so the drift is always about equal to the floor itself and
    EVERY run reports DRIFTING - which is worse than no metric, because it is a
    confident wrong answer. Steady state is taken to begin once the series first
    reaches half its peak."""
    vals = [key(s) for s in samples]
    peak = max(vals) or 1
    start = 0
    for i, v in enumerate(vals):
        if v >= 0.5 * peak:
            start = i
            break
    steady = samples[start:]
    if len(steady) < 4:
        steady = samples
    if len(steady) < buckets * 2:
        buckets = max(2, len(steady) // 2)
    t0 = steady[0].t
    span = (steady[-1].t - t0).total_seconds() or 1.0
    mins = [None] * buckets
    for s in steady:
        b = min(buckets - 1, int((s.t - t0).total_seconds() / span * buckets))
        v = key(s)
        if mins[b] is None or v < mins[b]:
            mins[b] = v
    return [m for m in mins if m is not None]


def summarize(path, threshold, force, files=0):
    samples, failed, nlines = parse(path)
    name = os.path.basename(path)
    print('=' * 72)
    print('%s  (%d lines, %d memstamp samples)' % (name, nlines, len(samples)))
    print('=' * 72)

    if failed and not force:
        print('RUN FAILED - an [ERROR] / exception is present in this log.')
        print('Refusing to report memory or gap statistics: a run that died early')
        print('yields a flat, gap-free summary that reads as a pass. Use --force to')
        print('override once you know why it failed.')
        return 1
    if failed:
        print('WARNING: this log contains an error; statistics below are suspect.')
    if len(samples) < 2:
        print('Not enough memstamp samples. Was the run given --timestamp --memstamp?')
        return 1

    dur = (samples[-1].t - samples[0].t).total_seconds()
    print('duration      : %d:%02d:%02d  (%s -> %s)' % (
        dur // 3600, (dur % 3600) // 60, dur % 60,
        samples[0].t.strftime('%H:%M:%S'), samples[-1].t.strftime('%H:%M:%S')))

    deltas = [(samples[i].t - samples[i - 1].t).total_seconds()
              for i in range(1, len(samples))]
    deltas_sorted = sorted(deltas)
    print('reporting gap : max %.0fs   median %.0fs   p95 %.0fs' % (
        deltas_sorted[-1], deltas_sorted[len(deltas_sorted) // 2],
        deltas_sorted[int(len(deltas_sorted) * 0.95)]))

    over = gaps(samples, threshold)
    if over:
        print('gaps >= %ds   : %d   <-- OVER THRESHOLD' % (threshold, len(over)))
        for d, t, msg in over[:10]:
            print('    %4.0fs at %s after: %s' % (d, t.strftime('%H:%M:%S'), msg[:78]))
        if len(over) > 10:
            print('    ... and %d more' % (len(over) - 10))
    else:
        print('gaps >= %ds   : 0   OK' % threshold)

    for label, key in (('managed', lambda s: s.managed), ('total', lambda s: s.total)):
        vals = [key(s) for s in samples]
        tr = troughs(samples, key)
        drift = tr[-1] - tr[0]
        # Only a RISING floor is the O(files) signature. A falling one means a
        # start-up spike draining away, which is a different (and benign) shape -
        # reporting both as "drifting" hides which one you are looking at.
        if drift > 0.10 * max(tr[0], 1):
            verdict = 'RISING'
        elif drift < -0.10 * max(tr[0], 1):
            verdict = 'FALLING'
        else:
            verdict = 'LEVEL'
        per_file = ''
        if files:
            # The number the scaling question actually turns on. GB/file times the
            # target file count says whether a bigger run fits in RAM.
            per_file = '   %+.0f MB/file' % (drift / float(files))
        print('%-13s : peak %7.1f GB   floor %5.1f -> %5.1f GB   drift %+.2f GB%s   %s' % (
            label + ' MB', max(vals) / 1024.0, tr[0] / 1024.0, tr[-1] / 1024.0,
            drift / 1024.0, per_file, verdict))
    return 0


# --- PNG output (matplotlib; optional dependency) ----------------------------

def plot(path, samples, out):
    """Render the same three series perfviz.html draws, so a PNG can be handed
    straight to a person instead of asking them to locate the log and paste it
    into the page.

    matplotlib is imported HERE, not at module scope, so the numeric summary -
    which is what actually decides anything - keeps working on a machine with
    nothing installed. Only --png needs the dependency.
    """
    try:
        import matplotlib
        matplotlib.use('Agg')                     # no display on a build agent
        import matplotlib.pyplot as plt
        import matplotlib.dates as mdates
    except ImportError:
        print('png           : skipped, matplotlib not installed'
              ' (pip install matplotlib). Text summary above is unaffected.')
        return

    ts = [s.t for s in samples]
    managed = [s.managed for s in samples]
    total = [s.total for s in samples]
    # Time gap belongs to the interval ENDING at each sample; the first has none.
    gapx = ts[1:]
    gapy = [(samples[i].t - samples[i - 1].t).total_seconds()
            for i in range(1, len(samples))]

    fig, ax = plt.subplots(figsize=(16, 6.5))
    ax2 = ax.twinx()
    # Same colours and z-order as perfviz.html so the two are read the same way.
    ax2.plot(gapx, gapy, '-o', color='#1f77b4', ms=2.0, lw=0.8,
             label='Time gap (sec)', zorder=1)
    ax.plot(ts, managed, '-o', color='#ff7f0e', ms=2.0, lw=0.8,
            label='Managed memory (MB)', zorder=2)
    ax.plot(ts, total, '-o', color='#2ca02c', ms=2.0, lw=0.8,
            label='Private memory (MB)', zorder=3)

    ax.set_ylabel('Memory (MB)')
    ax2.set_ylabel('Time gap (sec)')
    ax.set_xlabel('')
    ax.set_ylim(bottom=0)
    ax2.set_ylim(bottom=0)
    ax.grid(True, alpha=0.25, lw=0.5)
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    fig.autofmt_xdate()

    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, loc='upper center', bbox_to_anchor=(0.5, -0.12),
              ncol=3, frameon=False)

    peak = max(max(managed), max(total))
    ax.set_title('%s   -   peak %.1f GB, max gap %.0fs, %d samples'
                 % (os.path.basename(path), peak / 1024.0, max(gapy), len(samples)))
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    plt.close(fig)
    print('png           : %s' % out)


def compare(path_a, path_b, force, every_min=10):
    """Elapsed-matched A/B of two runs.

    Two runs of the same workload start at different wall-clock times, so their
    timestamps cannot be compared directly. This aligns both on seconds-since-
    first-sample and reports the delta at fixed elapsed offsets.

    Why per-sample and not just the summary: memstamp private bytes swing widely
    WITHIN a run (each sample catches the per-file transient at a different
    phase), so any single pair of readings proves nothing. What is diagnostic is
    the SIGN holding across many offsets - GC-timing noise flips sign, a real
    retention difference does not.

    It also works on a run still in progress: the table stops at whatever the
    shorter log has reached, so an A/B verdict is available long before the
    slower run finishes. That is the point - a 2h45m run should not have to
    finish before you learn whether the fix worked.
    """
    a_s, a_failed, _ = parse(path_a)
    b_s, b_failed, _ = parse(path_b)
    if not a_s or not b_s:
        print('COMPARE: need samples in both logs')
        return 1
    if (a_failed or b_failed) and not force:
        print('COMPARE SKIPPED - one of these logs shows a failure. Comparing a')
        print('dead run against a healthy one produces a meaningless delta. Use')
        print('--force once you know why it failed.')
        return 1

    def elapsed(samples):
        t0 = samples[0].t
        return [((s.t - t0).total_seconds(), s.managed, s.total) for s in samples]

    ea, eb = elapsed(a_s), elapsed(b_s)

    def at(rows, sec):
        best = None
        for e, mg, tot in rows:
            if e > sec:
                break
            best = (e, mg, tot)
        return best

    horizon = min(ea[-1][0], eb[-1][0])
    print()
    print('=' * 72)
    # Same basename is the COMMON case, not an edge case: an A/B of one harness
    # is two runs of the same log name in different directories. Disambiguate
    # with the parent directory so the header is not "A=x B=x".
    label_a, label_b = os.path.basename(path_a), os.path.basename(path_b)
    if label_a == label_b:
        label_a = os.path.join(os.path.basename(os.path.dirname(path_a)), label_a)
        label_b = os.path.join(os.path.basename(os.path.dirname(path_b)), label_b)
    print('ELAPSED-MATCHED COMPARE')
    print('  A = %s' % label_a)
    print('  B = %s' % label_b)
    print('=' * 72)
    print('elapsed |    A managed/total MB |    B managed/total MB |   delta total')
    print('-' * 72)
    signs = []
    for mins in range(0, int(horizon // 60) + 1, every_min):
        ra, rb = at(ea, mins * 60), at(eb, mins * 60)
        if not ra or not rb:
            continue
        d = rb[2] - ra[2]
        if mins:
            signs.append(d)
        print('%5d m | %9d / %9d | %9d / %9d | %+9d MB'
              % (mins, ra[1], ra[2], rb[1], rb[2], d))
    print('-' * 72)
    print('peak within the compared window:  A total %d MB   B total %d MB'
          % (max(r[2] for r in ea if r[0] <= horizon),
             max(r[2] for r in eb if r[0] <= horizon)))
    if signs:
        neg = sum(1 for d in signs if d < 0)
        print('B below A at %d of %d offsets%s' % (
            neg, len(signs),
            '  (consistent sign - a real retention difference, not GC noise)'
            if neg == len(signs) or neg == 0 else
            '  (mixed sign - treat as inconclusive; read the floor drift above)'))
    if ea[-1][0] != eb[-1][0]:
        print('NOTE: runs differ in length; compared only the first %.0f min.'
              % (horizon / 60))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('logs', nargs='+')
    ap.add_argument('--gap-threshold', type=float, default=30.0,
                    help='report gaps at least this many seconds (default 30)')
    ap.add_argument('--png', help='also write a PNG (single log only)')
    ap.add_argument('--files', type=int, default=0,
                    help='file count, to report floor drift per file (the scaling number)')
    ap.add_argument('--force', action='store_true',
                    help='report statistics even when the log shows a failure')
    ap.add_argument('--every', type=int, default=10, metavar='MIN',
                    help='elapsed-matched compare interval in minutes (default 10); '
                         'only used when exactly two logs are given')
    a = ap.parse_args()

    rc = 0
    for p in a.logs:
        if not os.path.exists(p):
            print('missing: %s' % p)
            rc = 1
            continue
        rc |= summarize(p, a.gap_threshold, a.force, a.files)
        if a.png and len(a.logs) == 1:
            s, failed, _ = parse(p)
            if len(s) >= 2 and (not failed or a.force):
                plot(p, s, a.png)
    if len(a.logs) == 2 and all(os.path.exists(p) for p in a.logs):
        rc |= compare(a.logs[0], a.logs[1], a.force, a.every)
    return rc


if __name__ == '__main__':
    sys.exit(main())
