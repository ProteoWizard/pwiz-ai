#!/usr/bin/env python3
"""A/B two Osprey runs on the pass-1 model-diagnostics, at BOTH scopes.

Written for the PICK_LDA evaluation, but nothing here is PICK_LDA-specific.

Why both scopes: OSPREY_PICK_LDA acts at PerFileScoring - it changes WHICH peak wins inside
one file. So the pass-1 RUN-scope view is the direct readout of the change, and the
EXPERIMENT-scope view is that effect after cross-run aggregation has had its say. Reporting only
the experiment number would confuse "the pick got better" with "aggregation liked the result".

Calibration is reported before sensitivity on purpose: a discovery count is only meaningful once
the true FDP behind it is known.

Usage: python picklda_compare.py <baseline_run_dir> <variant_run_dir>
"""
import json
import os
import re
import sys


def load_mdiag(run_dir):
    """The .data.json sidecar when present, else the JSON embedded in the HTML report."""
    dj = os.path.join(run_dir, 'out.model-diagnostics.data.json')
    if os.path.exists(dj):
        with open(dj, encoding='utf-8') as fh:
            return json.load(fh)
    html = os.path.join(run_dir, 'out.model-diagnostics.html')
    if not os.path.exists(html):
        raise SystemExit('no model-diagnostics in %s' % run_dir)
    with open(html, encoding='utf-8') as fh:
        t = fh.read()
    m = re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', t, re.S)
    if not m:
        raise SystemExit('no embedded JSON in %s' % html)
    return json.loads(m.group(1))


def view(d, scope, which_pass=1):
    for v in d.get('fdpViews', []):
        if v.get('pass') == which_pass and v.get('scope') == scope:
            return v
    return None


def at_q(v, qtarget=0.01):
    """(discoveries, true FDP) at the grid point at-or-below qtarget."""
    q, disc, fdp = v['q'], v['nTargetAccepted'], v['combined']
    best = None
    for i in range(len(q)):
        if abs(q[i] - qtarget) < 1e-9:
            return disc[i], fdp[i]
        if q[i] <= qtarget + 1e-12:
            best = i
    i = 0 if best is None else best
    return disc[i], fdp[i]


def at_true_fdp(v, target=0.01):
    """Discoveries at matched TRUE FDP - the oracle-fair count.

    Comparing raw disc@1%q across arms is unfair when the arms are calibrated differently: the
    better-calibrated arm gets penalised for being conservative. Matching on true FDP removes that.

    Convention is taken VERBATIM from extract_pass1_fdp.disc_at_fdp so these numbers splice into
    the existing cohort series: the MOST discoveries acceptable while true FDP stays <= target.
    A first-crossing scan is wrong - the curve is pure noise at tiny counts (FDP can be 0% or
    100% at a handful of accepted targets), so take the max over all qualifying grid points.

    Returns None when the only qualifying points are that low-count noise (guarded at 1% of the
    curve's peak), which is what happens at RUN scope where true FDP never falls to 1% at all.
    Reporting the noise value as if it were an operating point would be worse than reporting
    nothing.
    """
    disc, fdp = v['nTargetAccepted'], v['combined']
    cand = [disc[i] for i in range(len(fdp)) if fdp[i] <= target + 1e-12]
    if not cand:
        return None
    best = max(cand)
    peak = max(disc) if disc else 0
    return best if peak and best >= 0.01 * peak else None


def union_total(d):
    cu = ((d.get('crossRun') or {}).get('experiment') or {}).get('cumUnion') or []
    return cu[-1] if cu else None


def pct(new, old):
    if old in (None, 0) or new is None:
        return ''
    return '%+.1f%%' % (100.0 * (new - old) / old)


def delta(new, old):
    if new is None or old is None:
        return ''
    return '%+d' % (new - old)


def summarize(run_dir):
    d = load_mdiag(run_dir)
    out = {'name': os.path.basename(run_dir.rstrip('/\\')),
           'files': d.get('fileCount'),
           'modelComposite': d.get('modelComposite'),
           'union': union_total(d)}
    for scope in ('run', 'experiment'):
        v = view(d, scope)
        if v is None:
            continue
        disc, fdp = at_q(v)
        out[scope] = {'disc_at_q': disc, 'true_fdp_at_q': fdp, 'disc_at_true': at_true_fdp(v)}
    per_file = d.get('perFile') or []
    out['perFile'] = {r.get('file'): r.get('targets') for r in per_file if isinstance(r, dict)}
    # Per-file entrapment/target ratio is a file-level calibration readout that needs no oracle
    # curve: entrapment hits are known-false, so if a pick change buys targets by picking more
    # false peaks, this ratio rises even when the aggregate discovery count looks better.
    out['perFileEntrap'] = {r.get('file'): (r.get('entrapment'), r.get('targets'))
                            for r in per_file if isinstance(r, dict)}
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    a = summarize(sys.argv[1])
    b = summarize(sys.argv[2])

    print('baseline : %s  (%s files)' % (a['name'], a['files']))
    print('variant  : %s  (%s files)' % (b['name'], b['files']))
    if a['files'] != b['files']:
        print('  !! file counts differ - these arms are NOT comparable')
    print('')

    for scope in ('run', 'experiment'):
        if scope not in a or scope not in b:
            continue
        sa, sb = a[scope], b[scope]
        print('--- pass 1, %s scope ---' % scope.upper())
        print('  CALIBRATION  true FDP @ 1%% reported q : %.3f%%  ->  %.3f%%   (%s)'
              % (100 * sa['true_fdp_at_q'], 100 * sb['true_fdp_at_q'],
                 'better' if sb['true_fdp_at_q'] < sa['true_fdp_at_q'] else 'worse'))
        print('  SENSITIVITY  disc @ 1%% reported q     : %8d  ->  %8d   %s %s'
              % (sa['disc_at_q'], sb['disc_at_q'],
                 delta(sb['disc_at_q'], sa['disc_at_q']), pct(sb['disc_at_q'], sa['disc_at_q'])))
        print('  SENSITIVITY  disc @ matched 1%% TRUE   : %8s  ->  %8s   %s %s'
              % (sa['disc_at_true'] if sa['disc_at_true'] is not None else 'n/a', sb['disc_at_true'] if sb['disc_at_true'] is not None else 'n/a',
                 delta(sb['disc_at_true'], sa['disc_at_true']),
                 pct(sb['disc_at_true'], sa['disc_at_true'])))
        print('')

    print('--- model quality + aggregation survival ---')
    print('  modelComposite (target-decoy delta-mu) : %.4f  ->  %.4f   %s'
          % (a['modelComposite'] or 0, b['modelComposite'] or 0,
             pct(b['modelComposite'], a['modelComposite'])))
    if 'run' in a and 'run' in b and a['run']['disc_at_q'] and b['run']['disc_at_q']:
        ea = 100.0 * a['experiment']['disc_at_q'] / a['run']['disc_at_q']
        eb = 100.0 * b['experiment']['disc_at_q'] / b['run']['disc_at_q']
        print('  experiment-accepted / run-accepted     : %7.1f%%  ->  %7.1f%%   %+.1f pts'
              % (ea, eb, eb - ea))
        print('    (share of run-level acceptances surviving the experiment cut. NOTE: this is')
        print('     defined here as exp disc@1%q / run disc@1%q. It is NOT the same statistic as')
        print('     the "union efficiency" series in TODO-20260728 - do not splice them.)')
    print('')

    common = set(a['perFile']) & set(b['perFile'])
    if common:
        wins = sum(1 for f in common if (b['perFile'][f] or 0) > (a['perFile'][f] or 0))
        losses = sum(1 for f in common if (b['perFile'][f] or 0) < (a['perFile'][f] or 0))
        ta = sum(a['perFile'][f] or 0 for f in common)
        tb = sum(b['perFile'][f] or 0 for f in common)
        print('--- per-file targets (%d files) ---' % len(common))
        print('  total %d -> %d  (%s)   files up: %d   files down: %d   unchanged: %d'
              % (ta, tb, pct(tb, ta), wins, losses, len(common) - wins - losses))
        print('  A uniform direction across files means the change is GLOBAL (shared model or a')
        print('  systematic pick shift); a split means a few files drive it.')

        ea_n = sum((a['perFileEntrap'][f][0] or 0) for f in common)
        eb_n = sum((b['perFileEntrap'][f][0] or 0) for f in common)
        if ta and tb:
            print('  entrapment hits %d -> %d   entrapment/target %.3f%% -> %.3f%%  (%+.3f pts)'
                  % (ea_n, eb_n, 100.0 * ea_n / ta, 100.0 * eb_n / tb,
                     100.0 * eb_n / tb - 100.0 * ea_n / ta))
            print('  Entrapment hits are known-false, so a rise here means extra targets were')
            print('  bought by picking more false peaks - calibration, before any ID count.')


if __name__ == '__main__':
    main()
