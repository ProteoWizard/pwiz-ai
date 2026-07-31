#!/usr/bin/env python3
"""How often does the learned pick model actually choose a DIFFERENT peak than the product form?

The weights alone cannot answer this. The pick is an argmax over the CWT candidates inside one
precursor's RT window, and those candidates' features are strongly correlated - a rank function can
be radically re-weighted and still select the same candidate nearly every time. Tonight's mistake
was inferring a large effect from large weight differences; this measures the thing directly.

Only ONE Osprey run is needed: OSPREY_PICK_DUMP_CANDIDATES=1 records the four raw terms for every
candidate, so both argmaxes can be recomputed offline from the same candidate set. No second search,
and no confound from the two arms having scored different populations.

The target-vs-decoy split is the part that bears on the -16% modelComposite degradation: if the LDA
relocates DECOY peaks more often than target peaks, it is handing decoys extra chances to find a
good-looking peak, which compresses target-decoy separation and would explain a weaker trained
model without any appeal to library spectra.

Usage: python pick_disagreement.py <file.pick_candidates.tsv> [astral|stellar]

VALIDATION: the dump's own `is_picked` column records the argmax the run actually took, so on a
DEFAULT-pick dump argmax(product) must reproduce it exactly. This script checks that and refuses to
print a rate if it does not - the check is free, it sits in the same file, and it catches a wrong
tie-break, a transposed feature column, or the wrong instrument model, none of which are otherwise
visible. (It caught exactly that: an earlier version used Python's `max`, whose -0.0 == +0.0
blindness is the thing PeakDataExtractor.cs:361-369 deliberately fixed with IEEE-754 total order.
24.3% of rows in a real Astral dump have ln_intensity exactly 0, so the product is +/-0.0 and the
tie-break decides; it mismatched is_picked on 80,018 of 3.3M groups and shifted the published
rate by ~0.5 points.)
"""
import struct
import sys

# Verbatim from Osprey.Scoring/PickLdaModel.cs:76-84 (weights, means, scales), feature order
# coelution, ln_intensity, rt_penalty, median_polish.
MODELS = {
    'astral': {
        'w': [0.5348241578558818, 0.0041302671426268105, 0.3352868625222239, 0.7755828652613985],
        'm': [0.027393438120134818, 6.585876043601798, 0.939316453828307, 0.6880222328717774],
        's': [0.11714825645722571, 3.9104476306002494, 0.05338768554968953, 0.1461117956225306],
    },
    'stellar': {
        'w': [0.9933168416485256, 0.047052481253413006, 0.027130393118192445, 0.10184133676728513],
        'm': [0.14931086687377143, 9.15749607304815, 0.9158212545538758, 0.8904037620854307],
        's': [0.2074610054197197, 2.260347450504608, 0.07333900267211861, 0.08220791724094854],
    },
}


def lda_score(feats, mdl):
    return sum(mdl['w'][i] * (feats[i] - mdl['m'][i]) / mdl['s'][i] for i in range(4))


def product_score(feats):
    # coelution * rt_penalty * ln_intensity - median_polish is absent from the default form.
    return feats[0] * feats[2] * feats[1]


def total_order_key(x):
    """IEEE-754 total order as a sortable integer, matching Osprey's TotalOrder.Greater.

    PeakDataExtractor.cs:370 picks with TotalOrder.Greater, NOT `>`, because when intensityWeight
    is 0 the product is -0.0 or +0.0 depending on the sign of coelution, and `>` treats those as
    equal - which produced divergent picks vs Rust. Python's max() has the same blindness, so the
    comparison has to go through the bit pattern: negatives invert, positives set the sign bit,
    giving -0.0 < +0.0.
    """
    i = struct.unpack('<Q', struct.pack('<d', x))[0]
    return (~i & 0xFFFFFFFFFFFFFFFF) if i & 0x8000000000000000 else (i | 0x8000000000000000)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    model_name = (sys.argv[2] if len(sys.argv) > 2 else 'astral').lower()
    if model_name not in MODELS:
        raise SystemExit('unknown model %r; expected one of: %s\n%s'
                         % (model_name, ', '.join(sorted(MODELS)), __doc__))
    mdl = MODELS[model_name]

    stats = {'target': {'n': 0, 'multi': 0, 'disagree': 0},
             'decoy': {'n': 0, 'multi': 0, 'disagree': 0}}
    oracle = {'checked': 0, 'mismatch': 0}

    def finish(key, cands):
        """Score one precursor's candidate set. Called once per group as the file streams."""
        if key is None:
            return
        side = 'decoy' if key[1].strip().lower() in ('1', 'true') else 'target'
        st = stats[side]
        st['n'] += 1
        if len(cands) < 2:
            return  # One candidate: no choice to make, so no rank function can differ.
        st['multi'] += 1
        # argmax with the extractor's first-wins total-order tie-break (see total_order_key).
        best_p = max(cands, key=lambda c: (total_order_key(product_score(c[1])), -c[0]))
        best_l = max(cands, key=lambda c: (total_order_key(lda_score(c[1], mdl)), -c[0]))
        if best_p[0] != best_l[0]:
            st['disagree'] += 1
        # Free oracle: on a default-pick dump the product argmax IS what the run picked.
        picked = [c[0] for c in cands if c[2]]
        if len(picked) == 1:
            oracle['checked'] += 1
            if picked[0] != best_p[0]:
                oracle['mismatch'] += 1

    # PickCandidateDump.Flush writes rows ordered by (base_id, target-before-decoy, cand_index),
    # so consecutive rows sharing a key ARE one precursor's candidate set. Streaming group by
    # group keeps memory at one precursor instead of ~16M rows for this 1.65 GB dump.
    with open(path, encoding='utf-8') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {name: i for i, name in enumerate(header)}
        cur_key, cur = None, []
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) < len(header):
                continue
            key = (p[col['base_id']], p[col['is_decoy']])
            if key != cur_key:
                finish(cur_key, cur)
                cur_key, cur = key, []
            cur.append((int(p[col['cand_index']]),
                        (float(p[col['coelution']]), float(p[col['ln_intensity']]),
                         float(p[col['rt_penalty']]), float(p[col['median_polish']])),
                        p[col['is_picked']].strip().lower() in ('1', 'true')))
        finish(cur_key, cur)

    print('candidate dump: %s' % path)
    print('model         : %s (weights from PickLdaModel.cs; NOT recorded in the TSV, so this is'
          % model_name)
    print('                asserted by the caller - a Stellar dump scored with astral weights')
    print('                still prints a plausible-looking rate)')
    if oracle['checked']:
        bad = oracle['mismatch']
        print('oracle check  : product argmax vs the dump\'s own is_picked: %d/%d mismatched'
              % (bad, oracle['checked']))
        if bad:
            print('')
            print('  REFUSING to report a rate. On a DEFAULT-pick dump these must agree exactly.')
            print('  A mismatch means the replication is wrong (tie-break, feature column order,')
            print('  or the wrong model) OR the dump came from a PICK_LDA run, in which case the')
            print('  product argmax is not what was picked and this comparison is meaningless.')
            raise SystemExit(2)
    print('')
    for side in ('target', 'decoy'):
        st = stats[side]
        if not st['n']:
            continue
        pct_multi = 100.0 * st['multi'] / st['n']
        pct_dis_multi = 100.0 * st['disagree'] / st['multi'] if st['multi'] else 0.0
        pct_dis_all = 100.0 * st['disagree'] / st['n']
        print('%-7s precursors %7d   with >1 candidate %7d (%.1f%%)'
              % (side, st['n'], st['multi'], pct_multi))
        print('        product vs LDA pick DIFFERS on %d  = %.1f%% of contested, %.1f%% of all'
              % (st['disagree'], pct_dis_multi, pct_dis_all))
    t, d = stats['target'], stats['decoy']
    if t['multi'] and d['multi']:
        rt = 100.0 * t['disagree'] / t['multi']
        rd = 100.0 * d['disagree'] / d['multi']
        print('')
        print('decoy-minus-target disagreement on contested precursors: %+.1f pts' % (rd - rt))
        print('  > 0 means the LDA relocates DECOY peaks more often than target peaks, i.e. it')
        print('  gives the null extra chances to find a good-looking peak - which would compress')
        print('  target-decoy separation and is a candidate explanation for the -16% modelComposite.')
        print('  ~0 means the degradation comes from somewhere else.')


if __name__ == '__main__':
    main()
