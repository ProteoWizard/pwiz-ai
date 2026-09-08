"""Deep-compare two model-diagnostics reports' embedded JSON payloads.

Written for the Route A / Route B equivalence test (PR #4633): Route A folds the
first-pass report from the on-disk 1st-pass sidecars, Route B folds it from the
LIVE score-pass sink as Percolator scores each row. Two independent feeds
reducing to the same first-pass answer is the whole content of that test, so
everything the two feeds share must be equal.

The handful of fields that legitimately differ are dropped BY NAME rather than
absorbed by a tolerance, so a field going quietly wrong cannot hide inside a
fuzzy comparison:

  generatedUtc, ospreyVersion   render-time stamps, not results.
  completeness                  a statement about which PRODUCTS existed at
                                render time, so a cold page and a warm
                                regeneration legitimately differ while describing
                                the same first pass.
  featureCount, model,          a resumed/rehydrated run passes a null
  modelComposite                FeatureContributions and logs "first-pass model
                                not retrained on this run"; a cold run trains.
                                regression.ps1 already models this distinction as
                                Compare-DiagnosticsGolden -NoTrainedModel.

Everything else must match. Numbers compare EXACTLY by default: both sides reduce
the same rows in the same order, so a difference is a real difference rather than
a rounding artifact. --tol relaxes that only when a difference needs sizing.

    python Compare-DiagnosticsPayloads.py A.html B.html [--tol T] [--max N]
    python Compare-DiagnosticsPayloads.py --structure A.html A.html
    python Compare-DiagnosticsPayloads.py --selftest A.html

--selftest is the reason to trust a MATCH. A self-compare returning MATCH proves
nothing on its own: a walker that emitted no leaves, or a drop list that swallowed
the payload, passes it too. The mode perturbs a real field (must be reported), a
dropped field (must be ignored), and removes a subtree (must be reported).
"""
import argparse
import json
import math
import os
import re
import sys
import tempfile

PAYLOAD = re.compile(r'(<script[^>]*type="application/json"[^>]*>)(.*?)(</script>)', re.S)

DROP_KEYS = {
    'generatedUtc', 'ospreyVersion', 'completeness',
    'featureCount', 'model', 'modelComposite',
}

# Also model-derived, but NOT dropped - REPORTED SEPARATELY.
#
# ModelDiagnosticsData.Build sets ModelComposite, ModelDegenerate, FeatureHistEdges
# and Model inside one `if (contributions != null)` block, and FeatureCount from
# `contributions?.Features.Count ?? 0` right above it. So a rehydrated run leaves
# all FIVE at their defaults, not the three the drop list names: modelDegenerate
# stays false and featureHistEdges stays null for exactly the same reason
# featureCount stays 0.
#
# Widening DROP_KEYS to swallow them would weaken the test by hiding two more
# fields from it. Reporting them in their own bucket keeps the comparison total:
# a difference here is explained, a difference anywhere else is not.
MODEL_DERIVED = {'modelDegenerate', 'featureHistEdges'}


def read_payload(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    m = PAYLOAD.search(text)
    if not m:
        raise SystemExit('no application/json payload in %s (report format changed?)' % path)
    return json.loads(m.group(2).strip())


def walk(node, path, out):
    """Flatten to path -> scalar, skipping dropped keys wherever they appear."""
    if isinstance(node, dict):
        for k in sorted(node):
            if k in DROP_KEYS:
                continue
            walk(node[k], '%s.%s' % (path, k), out)
    elif isinstance(node, list):
        out[path + '.#len'] = len(node)
        for i, v in enumerate(node):
            walk(v, '%s[%d]' % (path, i), out)
    else:
        out[path] = node


def same(a, b, tol):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if isinstance(a, float) and math.isnan(a):
            return isinstance(b, float) and math.isnan(b)
        if tol == 0:
            return a == b
        return abs(a - b) <= tol * max(1.0, abs(a), abs(b))
    return a == b


def compare(path_a, path_b, tol, maxshow, quiet=False):
    fa, fb = {}, {}
    walk(read_payload(path_a), '', fa)
    walk(read_payload(path_b), '', fb)

    def is_model_derived(leaf):
        return any(part.split('[')[0] in MODEL_DERIVED for part in leaf.split('.'))

    only_a_all = sorted(set(fa) - set(fb))
    only_b_all = sorted(set(fb) - set(fa))
    shared = sorted(set(fa) & set(fb))
    diffs_all = [(k, fa[k], fb[k]) for k in shared if not same(fa[k], fb[k], tol)]

    # Split the model-derived leaves out of every bucket before judging.
    only_a = [k for k in only_a_all if not is_model_derived(k)]
    only_b = [k for k in only_b_all if not is_model_derived(k)]
    diffs = [d for d in diffs_all if not is_model_derived(d[0])]
    model_leaves = ([k for k in only_a_all if is_model_derived(k)]
                    + [k for k in only_b_all if is_model_derived(k)]
                    + [d[0] for d in diffs_all if is_model_derived(d[0])])

    if not quiet:
        print('A leaves: %d   B leaves: %d   shared: %d' % (len(fa), len(fb), len(shared)))
        print('only in A: %d   only in B: %d   differing shared: %d'
              % (len(only_a), len(only_b), len(diffs)))
        print('tolerance: %s' % ('exact' if tol == 0 else tol))
        if model_leaves:
            print('\n--- MODEL-DERIVED, expected to differ (%d leaf/leaves, not counted above)'
                  % len(model_leaves))
            print('    A rehydrated run leaves modelDegenerate=false and featureHistEdges=null')
            print('    for the same reason it leaves featureCount=0; a cold run trains.')
            for k in sorted(set(model_leaves))[:maxshow]:
                print('      %-64s A=%r B=%r'
                      % (k, fa.get(k, '<absent>'), fb.get(k, '<absent>')))

        for label, keys, src in (('ONLY IN A', only_a, fa), ('ONLY IN B', only_b, fb)):
            if keys:
                print('\n--- %s (first %d of %d)' % (label, min(maxshow, len(keys)), len(keys)))
                for k in keys[:maxshow]:
                    print('  %-70s %r' % (k, src[k]))

        if diffs:
            print('\n--- DIFFERING (first %d of %d)' % (min(maxshow, len(diffs)), len(diffs)))
            for k, va, vb in diffs[:maxshow]:
                print('  %-58s A=%-20r B=%r' % (k, va, vb))
            roll = {}
            for k, _va, _vb in diffs:
                top = '.'.join(k.split('.')[:3])
                roll[top] = roll.get(top, 0) + 1
            print('\n--- differing leaves by section')
            for k in sorted(roll, key=lambda x: -roll[x]):
                print('  %-60s %d' % (k, roll[k]))

    ok = not diffs and not only_a and not only_b
    if not quiet:
        print('\nRESULT: %s' % ('MATCH' if ok else 'DIFFERENCES FOUND'))
    return ok


def structure(paths):
    for label, path in zip(('A', 'B'), paths):
        print('=== %s: %s' % (label, path))
        doc = read_payload(path)
        for k in sorted(doc):
            v = doc[k]
            extra = ('len=%d' % len(v)) if isinstance(v, (list, dict)) else repr(v)
            print('  %-24s %-9s %s' % (k, type(v).__name__, extra[:110]))


def selftest(src):
    """Negative controls: prove the comparator reports what it must and drops what it must."""
    with open(src, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    m = PAYLOAD.search(text)
    if not m:
        raise SystemExit('no payload in %s' % src)

    def rewrite(mutator):
        doc = json.loads(m.group(2).strip())
        mutator(doc)
        fd, path = tempfile.mkstemp(suffix='.html')
        with os.fdopen(fd, 'w', encoding='utf-8') as fh2:
            fh2.write(text[:m.start(2)] + json.dumps(doc) + text[m.end(2):])
        return path

    def bump_real(doc):
        doc['nTarget'] = doc['nTarget'] + 1

    def bump_dropped(doc):
        doc['generatedUtc'] = 'MUTATED'
        doc['ospreyVersion'] = 'MUTATED'
        doc['featureCount'] = 9999
        doc['modelComposite'] = 1.234
        doc['model'] = [{'x': 1}]
        doc['completeness'] = {'mutated': True}

    def drop_subtree(doc):
        ca = doc.get('coAssignment') or {}
        if ca:
            ca.pop(sorted(ca)[0])

    def bump_model_derived(doc):
        doc['modelDegenerate'] = not doc.get('modelDegenerate', False)
        doc['featureHistEdges'] = [1.0, 2.0, 3.0]

    cases = (('perturbed real field', bump_real, False),
             ('perturbed dropped fields', bump_dropped, True),
             ('perturbed model-derived', bump_model_derived, True),
             ('removed subtree', drop_subtree, False))
    allok = True
    for name, mut, expect_match in cases:
        path = rewrite(mut)
        try:
            got = compare(src, path, 0.0, 0, quiet=True)
        finally:
            os.remove(path)
        ok = (got == expect_match)
        allok &= ok
        print('%-26s expect=%-18s got=%-18s %s'
              % (name, 'MATCH' if expect_match else 'DIFFERENCES',
                 'MATCH' if got else 'DIFFERENCES', 'OK' if ok else '*** FAIL ***'))
    print('\nSELFTEST: %s' % ('OK' if allok else 'FAILED'))
    return allok


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('reports', nargs='+')
    ap.add_argument('--tol', type=float, default=0.0)
    ap.add_argument('--max', type=int, default=40, help='differences to print')
    ap.add_argument('--structure', action='store_true')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()

    if args.selftest:
        return 0 if selftest(args.reports[0]) else 1
    if args.structure:
        structure(args.reports[:2] if len(args.reports) > 1 else args.reports * 2)
        return 0
    if len(args.reports) < 2:
        ap.error('two reports are required to compare')
    return 0 if compare(args.reports[0], args.reports[1], args.tol, args.max) else 1


if __name__ == '__main__':
    sys.exit(main())
