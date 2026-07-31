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
"""
import sys
from collections import defaultdict

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


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    mdl = MODELS[(sys.argv[2] if len(sys.argv) > 2 else 'astral').lower()]

    stats = {'target': {'n': 0, 'multi': 0, 'disagree': 0},
             'decoy': {'n': 0, 'multi': 0, 'disagree': 0}}

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
        # argmax with the same first-wins tie-break the extractor uses (strict >).
        best_p = max(cands, key=lambda c: (product_score(c[1]), -c[0]))
        best_l = max(cands, key=lambda c: (lda_score(c[1], mdl), -c[0]))
        if best_p[0] != best_l[0]:
            st['disagree'] += 1

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
                         float(p[col['rt_penalty']]), float(p[col['median_polish']]))))
        finish(cur_key, cur)

    print('candidate dump: %s' % path)
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
