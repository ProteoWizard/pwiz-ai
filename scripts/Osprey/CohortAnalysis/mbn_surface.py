#!/usr/bin/env python3
"""Harvest EVERY mean(best-N) probe run into one tidy table + the paper figure.

Generalizes extract_all.py: instead of a hard-coded (F, N) list it discovers arms from the
run-directory names, so new cohort sizes / N levels / replicate slices appear automatically.

Per arm (pass-1 experiment fdpView from out.model-diagnostics.data.json):
  disc@1%q     precursors accepted at reported experiment q <= 1%  (the as-shipped operating point)
  trueFDP@1%q  true combined entrapment FDP at that cut            (<=1% honest, >1% inflated)
  matchedTRUE  discoveries at matched 1% TRUE FDP                  (fair comparison at equal honesty)

N=1 IS the max/best-of-runs baseline (mean of the best 1 per-run score == max), so the
aggregation axis starts at 1 rather than treating max as a separate arm.

Usage:  python ai/.tmp/mbn_surface.py [--no-plot]
Writes: ai/.tmp/mbn_surface.csv, ai/.tmp/mbn_surface.png, ai/.tmp/mbn_surface.pdf
"""
import argparse
import csv
import json
import os
import re
import sys

# Where the Osprey run directories live, and where analysis products go. Both are overridable
# so this works on another machine (same convention as the other Osprey scripts, e.g.
# OSPREY_EXE / OSPREY_TESTDIR). Outputs default to ai/.tmp - never into the repo.
RUNS = os.environ.get('OSPREY_RUNS_DIR', 'D:/test/osprey-runs/sea-ad/runs')
OUT = os.environ.get(
    'OSPREY_ANALYSIS_OUT',
    os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 '..', '..', '..', '.tmp')))

# The pass-2 mode is a free token because it is no longer always 'percolator' - Osprey removed
# that mode, so arms taken after the removal are named for whichever mode ran (protein-compact by
# default). Every arm on disk today is still a percolator one; the widened pattern is what lets a
# post-removal arm be harvested at all. It does NOT make the two comparable - a surface must be
# built from one mode.
MODE = r'[a-z][a-z-]*'
# Arms from the systematic sweeps: ...-f<F>n<N>[s<SKIP>]  (s = files skipped -> replicate slice)
ARM_RE = re.compile(rf'^seaad-(\d+)files-libdecoy-r1\.0-{MODE}-f(\d+)n(\d+)(?:s(\d+))?$')
# Content-matched cohorts: ...-spread41n<N> (every 2nd file), ...-nopool75n<N> (pools excluded).
# These hold size roughly fixed and vary WHICH files are in the cohort, which is the axis that
# actually moved the effect once F=4..60 turned out to be flat.
CONTENT_RE = re.compile(rf'^seaad-(\d+)files-libdecoy-r1\.0-{MODE}-([a-z]+)(\d+)n(\d+)$')

# Arms that predate the f<F>n<N> naming, kept so the early anchors stay in the table.
LEGACY = {
    'pass2ab-82file-percolator-5day': (82, 1, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb2stream82': (82, 2, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb2stream82b': (82, 2, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb3stream82': (82, 3, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb4stream82': (82, 4, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb6stream82': (82, 6, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb8stream82': (82, 8, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb12stream82': (82, 12, 0),
    'seaad-82files-libdecoy-r1.0-percolator-mb20stream82': (82, 20, 0),
    'mb2-fpstream-20-maxstream': (20, 1, 0),
    'mb2-fpstream-20-mb2stream': (20, 2, 0),
}


def load(run_dir):
    """The model-diagnostics payload for a run, from the .data.json or embedded in the HTML."""
    dj = os.path.join(run_dir, 'out.model-diagnostics.data.json')
    html = os.path.join(run_dir, 'out.model-diagnostics.html')
    if os.path.exists(dj):
        with open(dj, encoding='utf-8') as fh:
            return json.load(fh)
    if os.path.exists(html):
        with open(html, encoding='utf-8') as fh:
            t = fh.read()
        mo = re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', t, re.S)
        if mo:
            return json.loads(mo.group(1))
    return None


def metrics(run_dir):
    """Pass-1 experiment metrics for one arm, or None if its mdiag is not readable yet.

    Returns disc_q1 / fdp_q1 / matched plus the k=1 over-admission slice from
    crossRun.experiment: how many accepted precursors were seen in exactly ONE run, what
    share of the accepted set that is, and that slice's own true entrapment FDP. Bin 0 is
    the 1-run bin (verified against the recorded 82-file numbers: 639 accepted / 20.57%).
    """
    d = load(run_dir)
    if d is None:
        return None
    vs = [x for x in d.get('fdpViews', []) if x.get('pass') == 1 and x.get('scope') == 'experiment']
    if not vs:
        return None
    v = vs[0]
    q, comb, disc = v['q'], v['combined'], v['nTargetAccepted']
    at1 = [i for i in range(len(q)) if q[i] <= 0.01 + 1e-12]
    if not at1:
        return None
    i = max(at1, key=lambda k: disc[k])
    matched = [disc[k] for k in range(len(comb)) if comb[k] <= 0.01 + 1e-12]
    if not matched:
        return None

    out = dict(disc_q1=disc[i], fdp_q1=comb[i], matched=max(matched),
               k1_acc=None, k1_share=None, k1_fdp=None)
    exp = (d.get('crossRun') or {}).get('experiment') or {}
    hist, ehist = exp.get('runCountHistogram'), exp.get('entrapmentFdpByRunCount')
    if hist:
        total = sum(hist)
        out['k1_acc'] = hist[0]
        out['k1_share'] = 100.0 * hist[0] / total if total else None
    if ehist:
        out['k1_fdp'] = 100.0 * ehist[0]
    return out


def classify(name):
    """(cohort label, F, N, kind) for an arm directory, or None if it is not one.

    The label is the comparison group: every arm sharing a label differs ONLY in N, so the gain
    is always a within-cohort A/B. 'primary' = first-F cohorts (the only ones on the size axis),
    'slice' = same size from a different part of the series, 'content' = size held, files chosen.
    """
    mo = ARM_RE.match(name)
    if mo:
        files, n, skip = int(mo.group(1)), int(mo.group(3)), int(mo.group(4) or 0)
        n = 1 if n == 0 else n              # n0 == max == mean(best-1)
        if skip:
            return f'{files}+{skip}', files, n, 'slice'
        return str(files), files, n, 'primary'
    mo = CONTENT_RE.match(name)
    if mo:
        files, kind, n = int(mo.group(1)), mo.group(2), int(mo.group(4))
        return f'{kind}{files}', files, (1 if n == 0 else n), 'content'
    if name in LEGACY:
        files, n, skip = LEGACY[name]
        return str(files), files, n, 'primary'
    return None


def discover():
    """All readable arms as {(label, N): dict(dir=..., F=..., kind=..., **metrics)}."""
    found = {}
    for name in sorted(os.listdir(RUNS)):
        path = os.path.join(RUNS, name)
        if not os.path.isdir(path):
            continue
        info = classify(name)
        if info is None:
            continue
        label, files, n, kind = info
        vals = metrics(path)
        if vals is None:
            continue                       # arm launched but not yet at its pass-1 mdiag
        if (label, n) not in found:         # systematic naming sorts before the legacy aliases
            found[(label, n)] = dict(vals, dir=name, F=files, kind=kind)
    return found


def tidy(found):
    """Add the within-cohort gain vs N=1 and return rows sorted by (kind, F, label, N)."""
    order = {'primary': 0, 'slice': 1, 'content': 2}
    rows = []
    for (label, n), v in found.items():
        base = found.get((label, 1))
        gain = 100.0 * (v['matched'] - base['matched']) / base['matched'] if base else None
        rows.append(dict(cohort=label, F=v['F'], N=n, kind=v['kind'], disc_q1=v['disc_q1'],
                         fdp_q1_pct=100 * v['fdp_q1'], matched=v['matched'], gain_pct=gain,
                         k1_acc=v['k1_acc'], k1_share_pct=v['k1_share'], k1_fdp_pct=v['k1_fdp'],
                         dir=v['dir']))
    rows.sort(key=lambda r: (order[r['kind']], r['F'], r['cohort'], r['N']))
    return rows


def report(rows):
    cohorts = []
    for r in rows:
        if r['cohort'] not in cohorts:
            cohorts.append(r['cohort'])
    print('===== N-curves per cohort  [disc@1%q | trueFDP@1%q | matchedTRUE | vs max || '
          'k=1 accepted (share) FDP] =====')
    for label in cohorts:
        rs = [r for r in rows if r['cohort'] == label]
        print(f'\n-- {label} ({rs[0]["F"]} files, {rs[0]["kind"]}) --')
        for r in rs:
            tag = 'max     ' if r['N'] == 1 else f'best-{r["N"]:<3}'
            gain = f'{r["gain_pct"]:+6.1f}%' if r['gain_pct'] is not None else '     ?'
            k1 = (f'{r["k1_acc"]:>5} ({r["k1_share_pct"]:4.1f}%) {r["k1_fdp_pct"]:5.2f}%'
                  if r['k1_acc'] is not None and r['k1_fdp_pct'] is not None else '')
            print(f'   {tag} {r["disc_q1"]:>7} | {r["fdp_q1_pct"]:6.3f}% | {r["matched"]:>7} | {gain}'
                  f'   f={r["N"]/r["F"]:.3f}  || {k1}')

    print('\n===== best-2 vs max, per cohort  [max | best-2 (trueFDP@1%q) | gain | k=1 slice FDP] =====')
    for label in cohorts:
        rs = [r for r in rows if r['cohort'] == label]
        b2 = next((r for r in rs if r['N'] == 2), None)
        mx = next((r for r in rs if r['N'] == 1), None)
        if not b2 or not mx or b2['gain_pct'] is None:
            continue
        k1 = (f'  k=1 FDP {mx["k1_fdp_pct"]:5.2f}% -> {b2["k1_fdp_pct"]:5.2f}%'
              if mx['k1_fdp_pct'] is not None and b2['k1_fdp_pct'] is not None else '')
        print(f'   {label:<10} max {mx["matched"]:>7} ({mx["fdp_q1_pct"]:.2f}%)  '
              f'best-2 {b2["matched"]:>7} ({b2["fdp_q1_pct"]:.2f}%)  -> {b2["gain_pct"]:+6.1f}%{k1}')

    print('\n===== best N per cohort (matchedTRUE) =====')
    for label in cohorts:
        rs = [r for r in rows if r['cohort'] == label and r['gain_pct'] is not None]
        if len(rs) < 2:
            continue
        best = max(rs, key=lambda r: r['matched'])
        print(f'   {label:<10} N*={best["N"]:<3} {best["gain_pct"]:+6.1f}%   '
              f'f*={best["N"]/best["F"]:.3f}')


def plot(rows, path_png, path_pdf):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.lines import Line2D

    primary = [r for r in rows if r['kind'] == 'primary']
    reps = [r for r in rows if r['kind'] != 'primary']
    sizes = sorted({r['F'] for r in primary})
    if not sizes:
        print('nothing to plot yet')
        return

    # Cohort size is ORDERED magnitude, so it gets one sequential ramp (light = small cohort,
    # dark = large) rather than cycled categorical hues -- the family reads as a progression
    # and stays legible in CVD and greyscale print.
    cmap = plt.get_cmap('viridis')
    span = (len(sizes) - 1) or 1
    color = {f: cmap(0.08 + 0.84 * i / span) for i, f in enumerate(sizes)}

    fig, axgrid = plt.subplots(2, 2, figsize=(13.0, 9.5))
    axes = axgrid.ravel()
    ink, muted = '#1a1a1a', '#6b6b6b'
    for ax in axes:
        ax.grid(True, which='major', color='#dcdcdc', linewidth=0.6, zorder=0)
        ax.set_axisbelow(True)
        for side in ('top', 'right'):
            ax.spines[side].set_visible(False)
        for side in ('left', 'bottom'):
            ax.spines[side].set_color('#b0b0b0')
        ax.tick_params(colors=muted, labelsize=9)

    # --- Panel A: sensitivity gain vs aggregation depth, one curve per cohort size ---
    ax = axes[0]
    ax.axhline(0, color=muted, linewidth=1.0, linestyle='--', zorder=1)
    for f in sizes:
        rs = [r for r in primary if r['F'] == f and r['gain_pct'] is not None]
        if len(rs) < 2:
            continue
        xs = [r['N'] for r in rs]
        ys = [r['gain_pct'] for r in rs]
        ax.plot(xs, ys, '-o', color=color[f], linewidth=2, markersize=5, zorder=3, label=f'{f} files')
        peak = max(rs, key=lambda r: r['gain_pct'])
        ax.plot([peak['N']], [peak['gain_pct']], 'o', color=color[f], markersize=9,
                markeredgecolor='white', markeredgewidth=2, zorder=4)
    ax.set_xscale('log', base=2)
    ax.set_xticks([1, 2, 3, 4, 6, 8, 12, 20, 30])
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_xlabel('aggregation depth N   (N=1 is max / best-of-runs)', color=ink, fontsize=10)
    ax.set_ylabel('discoveries vs max at matched 1% true FDP (%)', color=ink, fontsize=10)
    ax.set_title('A. Reproducibility aggregation gains with cohort size',
                 color=ink, fontsize=11, loc='left')
    # Cohort size is ordered, so its key is a discrete colorbar rather than a legend box that
    # would grow an entry per cohort and sit on top of the curves.
    from matplotlib.colors import BoundaryNorm, ListedColormap
    sm = plt.cm.ScalarMappable(cmap=ListedColormap([color[f] for f in sizes]),
                               norm=BoundaryNorm(range(len(sizes) + 1), len(sizes)))
    cb = fig.colorbar(sm, ax=ax, ticks=[i + 0.5 for i in range(len(sizes))], pad=0.02)
    cb.ax.set_yticklabels([str(f) for f in sizes], fontsize=8.5, color=muted)
    cb.set_label('cohort size (files)', color=ink, fontsize=9)
    cb.outline.set_visible(False)
    cb.ax.tick_params(length=0)

    # --- Panel B: calibration of the reported 1% q ---
    ax = axes[1]
    ax.axhline(1.0, color=muted, linewidth=1.0, linestyle='--', zorder=1)
    # Annotation hugs the line from below at the right edge: above it would collide with the title.
    ax.text(30, 0.985, 'nominal 1%', color=muted, fontsize=8.5, va='top', ha='right')
    for f in sizes:
        rs = [r for r in primary if r['F'] == f]
        if len(rs) < 2:
            continue
        ax.plot([r['N'] for r in rs], [r['fdp_q1_pct'] for r in rs], '-o',
                color=color[f], linewidth=2, markersize=5, zorder=3, label=f'{f} files')
    ax.set_ylim(top=1.04)
    ax.set_xscale('log', base=2)
    ax.set_xticks([1, 2, 3, 4, 6, 8, 12, 20, 30])
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_xlabel('aggregation depth N', color=ink, fontsize=10)
    ax.set_ylabel('true entrapment FDP at reported q <= 1% (%)', color=ink, fontsize=10)
    ax.set_title('B. Deeper aggregation makes the reported q conservative',
                 color=ink, fontsize=11, loc='left')

    # --- Panel D: the mechanism -- share of the accepted set seen in only ONE run ---
    # This is what the gain is bought with: deeper aggregation demotes the singletons, which
    # carry an order-of-magnitude worse true FDP than the reproducible acceptances.
    ax = axes[3]
    for f in sizes:
        rs = [r for r in primary if r['F'] == f and r['k1_share_pct'] is not None]
        if len(rs) < 2:
            continue
        ax.plot([r['N'] for r in rs], [r['k1_share_pct'] for r in rs], '-o',
                color=color[f], linewidth=2, markersize=5, zorder=3)
    ax.set_xscale('log', base=2)
    ax.set_xticks([1, 2, 3, 4, 6, 8, 12, 20, 30])
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_xlabel('aggregation depth N', color=ink, fontsize=10)
    ax.set_ylabel('accepted precursors seen in only 1 run (%)', color=ink, fontsize=10)
    ax.set_title('D. Mechanism: the leaky single-run acceptances are demoted',
                 color=ink, fontsize=11, loc='left')

    # --- Panel C: the best-2 gain as a function of cohort size ---
    ax = axes[2]
    ax.axhline(0, color=muted, linewidth=1.0, linestyle='--', zorder=1)
    xs, ys = [], []
    for f in sizes:
        b2 = next((r for r in primary if r['F'] == f and r['N'] == 2), None)
        if b2 and b2['gain_pct'] is not None:
            xs.append(f)
            ys.append(b2['gain_pct'])
    ax.plot(xs, ys, '-o', color='#31688e', linewidth=2, markersize=6, zorder=3, label='best-2 vs max')
    # Content-matched cohorts (different files, comparable size) sit as labelled points: they do
    # not belong on a size trend line, and they are the arms that test what the effect depends on.
    alt = [r for r in reps if r['N'] == 2 and r['gain_pct'] is not None]
    if alt:
        ax.plot([r['F'] for r in alt], [r['gain_pct'] for r in alt], '^', color='#c94f4f',
                markersize=9, markeredgecolor='white', markeredgewidth=1.5, linestyle='none',
                zorder=5, label='same size, different files')
        for r in alt:
            ax.annotate(r['cohort'], (r['F'], r['gain_pct']), textcoords='offset points',
                        xytext=(8, -3), fontsize=8.5, color='#c94f4f')
    # The peak-N envelope: what the best available N buys, which is what an auto-N rule targets.
    px, py = [], []
    for f in sizes:
        rs = [r for r in primary if r['F'] == f and r['gain_pct'] is not None]
        if len(rs) >= 2:
            best = max(rs, key=lambda r: r['gain_pct'])
            px.append(f)
            py.append(best['gain_pct'])
    if px:
        ax.plot(px, py, '-s', color='#addc30', linewidth=2, markersize=5, zorder=2,
                label='best available N')
    ax.set_xscale('log', base=2)
    ax.set_xticks(sizes)
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_xlabel('cohort size (files)', color=ink, fontsize=10)
    ax.set_ylabel('discoveries vs max at matched 1% true FDP (%)', color=ink, fontsize=10)
    ax.set_title('C. The gain grows with cohort size', color=ink, fontsize=11, loc='left')
    ax.legend(frameon=False, fontsize=9, labelcolor=ink)

    fig.tight_layout()
    fig.savefig(path_png, dpi=200)
    fig.savefig(path_pdf)
    print(f'\nwrote {path_png}\nwrote {path_pdf}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--no-plot', action='store_true')
    args = ap.parse_args()

    found = discover()
    if not found:
        print(f'no readable arms under {RUNS}')
        return 1
    rows = tidy(found)
    report(rows)

    csv_path = os.path.join(OUT, 'mbn_surface.csv')
    with open(csv_path, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=['cohort', 'F', 'N', 'kind', 'disc_q1', 'fdp_q1_pct',
                                           'matched', 'gain_pct', 'k1_acc', 'k1_share_pct',
                                           'k1_fdp_pct', 'dir'])
        w.writeheader()
        w.writerows(rows)
    print(f'\nwrote {csv_path}  ({len(rows)} arms)')

    if not args.no_plot:
        plot(rows, os.path.join(OUT, 'mbn_surface.png'), os.path.join(OUT, 'mbn_surface.pdf'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
