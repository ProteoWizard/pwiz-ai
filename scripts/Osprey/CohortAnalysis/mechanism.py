#!/usr/bin/env python3
"""WHY does sensitivity fall as runs accumulate, and what does mean(best-N) restore?

No new runs: every mdiag already carries the pieces.

  crossRun.perRun.unionFdp[i]   true entrapment FDP of the UNION of accepted precursors after
                                i+1 files. The experiment-wide MAX score is a union-like
                                statistic (one good run is enough), so this curve IS the null
                                accumulating with run count. Its growth is the mechanism.
  cumUnion / cumUnionEntrapment the counts behind it - real vs entrapment growth rates.
  crossRun.experiment.*         the k-resolved view of the ACCEPTED set: how many acceptances
                                rest on exactly k runs and the true FDP of each k slice.
  scores.decoyMean/Std          the per-precursor score histogram by class (a control: if this
                                is identical between the max and best-N arms, the histogram is
                                aggregation-independent and cannot show the aggregate null).

Usage:  python ai/.tmp/mechanism.py [--plot]
Writes: ai/.tmp/mechanism.txt (full detail), ai/.tmp/mechanism_union.png (with --plot)
"""
import argparse
import os
import sys

import mbn_surface as M

OUT = M.OUT


def arms():
    """{(cohort, N): dir name} for every readable arm, via the shared classifier."""
    found = {}
    for name in sorted(os.listdir(M.RUNS)):
        if not os.path.isdir(os.path.join(M.RUNS, name)):
            continue
        info = M.classify(name)
        if not info:
            continue
        label, files, n, kind = info
        if M.metrics(os.path.join(M.RUNS, name)) is None:
            continue
        found.setdefault((label, n), (name, files, kind))
    return found


def k_slices(exp):
    """FDP and share of the accepted set for k=1, 2, 3-5, >=6 runs (bin 0 == 1 run)."""
    hist = exp.get('runCountHistogram') or []
    fdp = exp.get('entrapmentFdpByRunCount') or []
    ent = exp.get('entrapmentRunCountHistogram') or []
    total = sum(hist) or 1
    out = {}
    for name, lo, hi in (('k=1', 0, 1), ('k=2', 1, 2), ('k=3-5', 2, 5), ('k>=6', 5, len(hist))):
        n = sum(hist[lo:hi])
        e = sum(ent[lo:hi]) if ent else 0
        # Blend the per-k FDP by acceptance count when a slice spans several k bins.
        if n and fdp:
            num = sum(hist[i] * fdp[i] for i in range(lo, min(hi, len(fdp))))
            blended = num / n
        else:
            blended = float('nan')
        out[name] = (n, 100.0 * n / total, 100.0 * blended, e)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plot', action='store_true')
    args = ap.parse_args()

    found = arms()
    lines = []
    union_curves = {}

    lines.append('===== 1. UNION FDP GROWTH (max arms): the null accumulating with run count =====')
    lines.append('  unionFdp[i] = true FDP of the accepted-precursor union after i+1 files.')
    lines.append(f'{"cohort":<10} {"F":>3} {"FDP@1":>7} {"FDP@half":>9} {"FDP@last":>9} '
                 f'{"real/file":>10} {"entrap/file":>12}')
    for (label, n), (name, files, kind) in sorted(found.items(), key=lambda kv: (kv[1][1], kv[0][0])):
        if n != 1:
            continue
        d = M.load(os.path.join(M.RUNS, name))
        pr = ((d.get('crossRun') or {}).get('perRun')) or {}
        uf, cu, ce = pr.get('unionFdp'), pr.get('cumUnion'), pr.get('cumUnionEntrapment')
        if not uf or not cu:
            continue
        union_curves[label] = (files, uf, cu, ce)
        half = len(uf) // 2
        # Marginal growth per added file over the second half of the series.
        dr = (cu[-1] - cu[half]) / max(1, len(uf) - 1 - half)
        de = ((ce[-1] - ce[half]) / max(1, len(uf) - 1 - half)) if ce else float('nan')
        lines.append(f'{label:<10} {files:>3} {100*uf[0]:>6.2f}% {100*uf[half]:>8.2f}% '
                     f'{100*uf[-1]:>8.2f}% {dr:>10.0f} {de:>12.1f}')

    lines.append('')
    lines.append('===== 1b. MARGINAL PURITY of the last files added =====')
    lines.append('  The tool\'s union FDP is ~2*entrap/total (1:1 entrapment), so the same estimator')
    lines.append('  applied to the INCREMENT says how false the newly-added union members are.')
    lines.append(f'{"cohort":<10} {"F":>3} {"marg FDP last 25%":>18} {"marg FDP last 10 files":>23}')
    for label, (files, uf, cu, ce) in sorted(union_curves.items(), key=lambda kv: kv[1][0]):
        if not ce or len(cu) < 4:
            continue

        def marg(lo):
            dt, de = cu[-1] - cu[lo], ce[-1] - ce[lo]
            return 200.0 * de / dt if dt > 0 else float('nan')

        q3 = int(len(cu) * 0.75)
        last10 = max(0, len(cu) - 11)
        lines.append(f'{label:<10} {files:>3} {marg(q3):>17.1f}% {marg(last10):>22.1f}%')

    lines.append('')
    lines.append('===== 2. ACCEPTED SET BY RUN COUNT k  [n (share) FDP] =====')
    for (label, n), (name, files, kind) in sorted(found.items(), key=lambda kv: (kv[1][1], kv[0][0], kv[0][1])):
        if n not in (1, 2):
            continue
        d = M.load(os.path.join(M.RUNS, name))
        exp = ((d.get('crossRun') or {}).get('experiment')) or {}
        ks = k_slices(exp)
        tag = 'max   ' if n == 1 else 'best-2'
        cells = '  '.join(f'{k}: {v[0]:>5} ({v[1]:4.1f}%) {v[2]:5.2f}%' for k, v in ks.items())
        lines.append(f'{label:<10} {files:>3} {tag}  {cells}')

    lines.append('')
    lines.append('===== 2b. WHERE THE GAIN COMES FROM: acceptance delta by k slice (max -> best-2) =====')
    lines.append('  Negative k=1 = leaky singletons demoted. Positive k>=2 = reproducible precursors')
    lines.append('  admitted because demoting the singletons bought FDR headroom.')
    lines.append(f'{"cohort":<10} {"F":>3} {"d k=1":>7} {"d k=2":>7} {"d k=3-5":>9} {"d k>=6":>8} '
                 f'{"net":>7}')
    for label in sorted({k[0] for k in found}, key=lambda s: found[(s, 1)][1] if (s, 1) in found else 0):
        if (label, 1) not in found or (label, 2) not in found:
            continue
        a = k_slices(((M.load(os.path.join(M.RUNS, found[(label, 1)][0])).get('crossRun') or {})
                      .get('experiment')) or {})
        b = k_slices(((M.load(os.path.join(M.RUNS, found[(label, 2)][0])).get('crossRun') or {})
                      .get('experiment')) or {})
        d = {k: b[k][0] - a[k][0] for k in a}
        lines.append(f'{label:<10} {found[(label, 1)][1]:>3} {d["k=1"]:>+7} {d["k=2"]:>+7} '
                     f'{d["k=3-5"]:>+9} {d["k>=6"]:>+8} {sum(d.values()):>+7}')

    lines.append('')
    lines.append('===== 3. CONTROL: is the per-precursor score histogram aggregation-dependent? =====')
    for label in sorted({k[0] for k in found}, key=lambda s: (len(s), s)):
        pair = []
        for n in (1, 2):
            if (label, n) not in found:
                continue
            d = M.load(os.path.join(M.RUNS, found[(label, n)][0]))
            sc = d.get('scores') or {}
            pair.append((n, sc.get('decoyMean'), sc.get('decoyStd'), sc.get('decoyN')))
        if len(pair) == 2:
            same = (pair[0][1] == pair[1][1] and pair[0][2] == pair[1][2])
            lines.append(f'{label:<10} decoyMean max={pair[0][1]:.6f} best-2={pair[1][1]:.6f}  '
                         f'{"IDENTICAL" if same else "DIFFERS"}')

    txt = '\n'.join(lines)
    with open(os.path.join(OUT, 'mechanism.txt'), 'w', encoding='utf-8') as fh:
        fh.write(txt + '\n')
    print(txt)

    if args.plot and union_curves:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(1, 2, figsize=(12.5, 5.0))
        sizes = sorted({v[0] for v in union_curves.values()})
        cmap = plt.get_cmap('viridis')
        span = (len(sizes) - 1) or 1
        color = {f: cmap(0.08 + 0.84 * sizes.index(f) / span) for f in sizes}
        ink, muted = '#1a1a1a', '#6b6b6b'
        for ax in axes:
            ax.grid(True, color='#dcdcdc', linewidth=0.6)
            ax.set_axisbelow(True)
            for s in ('top', 'right'):
                ax.spines[s].set_visible(False)
            ax.tick_params(colors=muted, labelsize=9)
        for label, (files, uf, cu, ce) in sorted(union_curves.items(), key=lambda kv: kv[1][0]):
            xs = range(1, len(uf) + 1)
            axes[0].plot(xs, [100 * u for u in uf], '-', color=color[files], linewidth=2)
            axes[1].plot(xs, cu, '-', color=color[files], linewidth=2)
        axes[0].set_xlabel('files accumulated', color=ink, fontsize=10)
        axes[0].set_ylabel('true FDP of the accepted union (%)', color=ink, fontsize=10)
        axes[0].set_title('Union FDP grows with every added run', color=ink, fontsize=11, loc='left')
        axes[1].set_xlabel('files accumulated', color=ink, fontsize=10)
        axes[1].set_ylabel('precursors in the union', color=ink, fontsize=10)
        axes[1].set_title('Union size saturates while its FDP does not',
                          color=ink, fontsize=11, loc='left')
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, 'mechanism_union.png'), dpi=200)
        print(f'\nwrote {os.path.join(OUT, "mechanism_union.png")}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
