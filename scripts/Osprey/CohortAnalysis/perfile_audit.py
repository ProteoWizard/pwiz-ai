#!/usr/bin/env python3
"""Hunt for problematic files behind the F=40 -> F=82 collapse in the max baseline.

Every model-diagnostics payload carries a per-file passing table (targets / decoys /
entrapment at the reported FDR) and per-run detection counts, so this needs no new runs.

Three views:
  1. PER-FILE OUTLIERS in the 82-file cohort - robust z-scores (median / MAD) on passing
     targets and on the per-file entrapment rate. A file that passes far fewer targets, or
     whose passing set is disproportionately entrapment, is a candidate bad file.
  2. CONTAMINATION - for the files present in BOTH a small cohort and the 82-file cohort,
     how much each file's passing count changes when the other files join. The first-pass
     model and the experiment-wide q are global, so a few bad files can depress every
     file's passing count. That is the difference between "82 files is genuinely harder"
     and "a handful of files poison the shared model".
  3. WHO GAINS from mean(best-N) - the same per-file delta between the max and best-N arms
     of one cohort, to see whether the recovery is spread across files or concentrated in
     the files that the max baseline lost.

Usage: python ai/.tmp/perfile_audit.py
"""
import os
import statistics as st

import mbn_surface as M

RUNS = M.RUNS
ARMS = {
    'max82': 'pass2ab-82file-percolator-5day',
    'mb2-82': 'seaad-82files-libdecoy-r1.0-percolator-mb2stream82b',
    'max40': 'seaad-40files-libdecoy-r1.0-percolator-f40n0',
    'max60': 'seaad-60files-libdecoy-r1.0-percolator-f60n0',
    'mb2-40': 'seaad-40files-libdecoy-r1.0-percolator-f40n2',
    'max20': 'seaad-20files-libdecoy-r1.0-percolator-f20n0',
    'max30': 'seaad-30files-libdecoy-r1.0-percolator-f30n0',
}


def per_file(arm_dir):
    """{file name: (targets, decoys, entrapment)} for one arm, or {} if unavailable."""
    d = M.load(os.path.join(RUNS, arm_dir))
    if not d:
        return {}
    return {r['file']: (r['targets'], r['decoys'], r['entrapment']) for r in d.get('perFile') or []}


def robust_z(vals):
    """Median/MAD z-scores - resistant to the outliers we are looking for."""
    med = st.median(vals)
    mad = st.median([abs(v - med) for v in vals]) or 1e-9
    return med, mad, [(v - med) / (1.4826 * mad) for v in vals]


def short(name):
    """SEA-AD-0007_7160_A08_012 -> 0007_A08 (donor + plate well, enough to identify)."""
    parts = name.split('_')
    donor = next((p for p in parts if p.startswith('SEA-AD-')), '?').replace('SEA-AD-', '')
    return f'{donor}_{parts[-2] if len(parts) > 2 else "?"}'


def main():
    tables = {k: per_file(v) for k, v in ARMS.items()}
    for k, v in tables.items():
        print(f'{k:8} {len(v):>3} files' + ('' if v else '   (missing)'))
    t82 = tables['max82']
    if not t82:
        return 1

    names = list(t82)
    targets = [t82[n][0] for n in names]
    rates = [1e4 * t82[n][2] / max(1, t82[n][0]) for n in names]   # entrapment per 10k targets
    med_t, mad_t, z_t = robust_z(targets)
    med_r, mad_r, z_r = robust_z(rates)
    print(f'\n===== 1. PER-FILE OUTLIERS, 82-file cohort (max arm) =====')
    print(f'passing targets: median {med_t:,.0f}  MAD {mad_t:,.0f}   '
          f'entrapment/10k targets: median {med_r:.1f}  MAD {mad_r:.1f}')
    rows = sorted(zip(names, targets, rates, z_t, z_r), key=lambda r: r[3])
    print('  weakest by passing targets:')
    for n, t, r, zt, zr in rows[:10]:
        print(f'   {short(n):<12} targets {t:>6,}  z={zt:+5.1f}   entrap/10k {r:5.1f} z={zr:+5.1f}')
    print('  highest entrapment rate:')
    for n, t, r, zt, zr in sorted(rows, key=lambda r: -r[4])[:10]:
        print(f'   {short(n):<12} targets {t:>6,}  z={zt:+5.1f}   entrap/10k {r:5.1f} z={zr:+5.1f}')

    print('\n===== 2. CONTAMINATION: the same file, as the cohort around it grows (max arms) =====')
    print('  Run-level q is computed WITHIN a file, so the only cross-file channel is the shared')
    print('  trained model. A uniform loss here is model degradation, not a few bad files.')
    for small, large in (('max20', 'max40'), ('max40', 'max60'), ('max60', 'max82'),
                         ('max40', 'max82'), ('max20', 'max82')):
        base, big = tables.get(small), tables.get(large)
        if not base or not big:
            continue
        shared = [n for n in base if n in big]
        deltas = [(n, base[n][0], big[n][0], 100.0 * (big[n][0] - base[n][0]) / max(1, base[n][0]))
                  for n in shared]
        pcts = [d[3] for d in deltas]
        print(f'\n-- {small} -> {large} ({len(shared)} shared files) --')
        print(f'   per-file passing change: median {st.median(pcts):+.1f}%  '
              f'min {min(pcts):+.1f}%  max {max(pcts):+.1f}%  '
              f'({sum(1 for p in pcts if p < 0)}/{len(pcts)} files lose)')
        for n, b, a, p in sorted(deltas, key=lambda d: d[3])[:5]:
            print(f'     worst {short(n):<12} {b:>6,} -> {a:>6,}  {p:+6.1f}%')

    print('\n===== 3. WHO GAINS from mean(best-2) =====')
    for mx, mb, label in (('max82', 'mb2-82', '82 files'), ('max40', 'mb2-40', '40 files')):
        a, b = tables.get(mx), tables.get(mb)
        if not a or not b:
            continue
        shared = [n for n in a if n in b]
        deltas = [(n, a[n][0], b[n][0], 100.0 * (b[n][0] - a[n][0]) / max(1, a[n][0])) for n in shared]
        pcts = [d[3] for d in deltas]
        gain_tot = sum(d[2] - d[1] for d in deltas)
        print(f'\n-- {label}: max -> best-2, per-file passing --')
        print(f'   median {st.median(pcts):+.1f}%   min {min(pcts):+.1f}%   max {max(pcts):+.1f}%   '
              f'files improved {sum(1 for p in pcts if p > 0)}/{len(pcts)}   net {gain_tot:+,}')
        for n, x, y, p in sorted(deltas, key=lambda d: -d[3])[:5]:
            print(f'     best  {short(n):<12} {x:>6,} -> {y:>6,}  {p:+6.1f}%')
        for n, x, y, p in sorted(deltas, key=lambda d: d[3])[:3]:
            print(f'     worst {short(n):<12} {x:>6,} -> {y:>6,}  {p:+6.1f}%')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
