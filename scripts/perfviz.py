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
a fresh machine with nothing installed. The PNG is written by hand (PNG is just
zlib-compressed scanlines); there is no matplotlib here on purpose.

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
import struct
import sys
import zlib

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


# --- minimal PNG output (stdlib only) ---------------------------------------

def _png(path, w, h, px):
    raw = b''.join(b'\x00' + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    with open(path, 'wb') as fh:
        fh.write(b'\x89PNG\r\n\x1a\n')
        fh.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        fh.write(chunk(b'IDAT', zlib.compress(raw, 6)))
        fh.write(chunk(b'IEND', b''))


def plot(path, samples, out):
    W, H, M = 1400, 560, 40
    px = bytearray([255]) * (W * H * 3)

    def dot(x, y, rgb):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 3
            px[i], px[i + 1], px[i + 2] = rgb

    def line(x0, y0, x1, y1, rgb):
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx - dy
        while True:
            dot(x0, y0, rgb)
            dot(x0, y0 + 1, rgb)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    for x in range(M, W - M):
        dot(x, H - M, (0, 0, 0))
    for y in range(M, H - M):
        dot(M, y, (0, 0, 0))

    t0 = samples[0].t
    span = (samples[-1].t - t0).total_seconds() or 1.0
    vmax = max(max(s.managed, s.total) for s in samples) or 1
    for y in range(1, 5):                       # gridlines at 20/40/60/80%
        gy = int(H - M - (H - 2 * M) * y / 5.0)
        for x in range(M, W - M, 6):
            dot(x, gy, (210, 210, 210))

    def xy(s, val):
        return (int(M + (s.t - t0).total_seconds() / span * (W - 2 * M)),
                int(H - M - val / float(vmax) * (H - 2 * M)))

    for key, rgb in ((lambda s: s.total, (44, 160, 44)),
                     (lambda s: s.managed, (255, 127, 14))):
        prev = None
        for s in samples:
            cur = xy(s, key(s))
            if prev:
                line(prev[0], prev[1], cur[0], cur[1], rgb)
            prev = cur
    _png(out, W, H, px)
    print('png           : %s   (green=total, orange=managed, y-max %.1f GB)'
          % (out, vmax / 1024.0))


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
    return rc


if __name__ == '__main__':
    sys.exit(main())
