#!/usr/bin/env python3
"""Compare accepted pass-1 entrapment peptides against their paired source target.

Answers two questions on the PASS-1 accepted set (experiment-wide q <= 1%), not on the pass-2
blib:

  1. How does an accepted entrapment peptide score relative to its source target?
  2. Are they scoring the SAME PEAK -- i.e. is the entrapment hit riding the target's signal?

    python pass1_compare.py <dataset.json> <label>
"""
import bisect
import csv
import json
import statistics as st
import sys

MANIFEST = r'D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment\osprey_library_db_pairing.tsv'
RT_SAME = 0.05        # minutes; apex agreement below this is the same chromatographic peak

AA = dict(zip("GASPVTCLINDQKEMHFRYW",
              [57.02146, 71.03711, 87.03203, 97.05276, 99.06841, 101.04768, 103.00919,
               113.08406, 113.08406, 114.04293, 115.02694, 128.05858, 128.09496, 129.04259,
               131.04049, 137.05891, 147.06841, 156.10111, 163.06333, 186.07931]))
H2O, PROT = 18.010565, 1.007276


def ladder(p):
    b, s = [], 0.0
    for ch in p[:-1]:
        s += AA.get(ch, 0.0); b.append(s + PROT)
    y, s = [], 0.0
    for ch in reversed(p[1:]):
        s += AA.get(ch, 0.0); y.append(s + H2O + PROT)
    return sorted(b + y)


def overlap(a, t, ppm=10.0):
    la, lt = ladder(a), ladder(t)
    if not la:
        return 0.0
    m = 0
    for x in la:
        tol = x * ppm / 1e6
        i = bisect.bisect_left(lt, x - tol)
        if i < len(lt) and lt[i] <= x + tol:
            m += 1
    return m / len(la)


def ident(a, t):
    n = min(len(a), len(t))
    return sum(1 for i in range(n) if a[i] == t[i]) / max(len(a), len(t))


def main():
    d = json.load(open(sys.argv[1]))
    label = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
    info = {int(k): v for k, v in d['info'].items()}
    peaks = {int(k): {int(f): rt for f, rt in v.items()} for k, v in d['peaks'].items()}
    nfiles = len(d['files'])

    ent = {e: v for e, v in info.items() if '_p_target' in (v[1] or '')}
    # sequence -> entry_id for the accepted TARGET side (exclude entrapment and decoys)
    tgt_by_seq = {}
    for e, v in info.items():
        if '_p_target' in (v[1] or '') or 'decoy' in (v[1] or '').lower():
            continue
        cur = tgt_by_seq.get(v[0])
        if cur is None or v[2] < info[cur][2]:
            tgt_by_seq[v[0]] = e

    ent_seqs = {v[0] for v in ent.values()}
    pidx, tseq = {}, {}
    with open(MANIFEST, newline='', encoding='utf-8') as fh:
        for row in csv.DictReader(fh, delimiter='\t'):
            t, s, k = row['peptide_type'], row['sequence'], row['peptide_pair_index']
            if t == 'p_target' and s in ent_seqs:
                pidx[s] = k
            elif t == 'target':
                tseq[k] = s

    rows = []
    for e, v in ent.items():
        eseq, _, eq = v
        t = tseq.get(pidx.get(eseq, ''), None)
        if not t:
            continue
        te = tgt_by_seq.get(t)
        r = dict(eseq=eseq, tseq=t, eq=eq, id=ident(eseq, t), ov=overlap(eseq, t),
                 tacc=te is not None, tq=info[te][2] if te else None)
        if te is not None:
            pe, pt = peaks.get(e, {}), peaks.get(te, {})
            shared = sorted(set(pe) & set(pt))
            if shared:
                diffs = [abs(pe[f] - pt[f]) for f in shared]
                r['nshared'] = len(shared)
                r['med_drt'] = st.median(diffs)
                r['frac_same_peak'] = sum(1 for x in diffs if x <= RT_SAME) / len(diffs)
        rows.append(r)

    near = [r for r in rows if r['id'] > 0.5 or r['ov'] > 0.4]
    far = [r for r in rows if not (r['id'] > 0.5 or r['ov'] > 0.4)]
    print(f'=== {label} ===  {nfiles} files')
    print(f'accepted pass-1 entry_ids {len(info):,}   entrapment {len(ent):,}   '
          f'paired to a target {len(rows):,}')
    print(f'   near-copy (filter-rejectable) {len(near):,}   dissimilar {len(far):,}   '
          f'-> {len(near)/max(len(rows),1)*100:.1f}% rejectable\n')

    print(f"{'group':<26}{'n':>5}{'target also acc':>17}{'ent q':>11}{'tgt q':>11}{'ent/tgt':>9}")
    for g, lbl in ((near, 'near-copy'), (far, 'dissimilar'), (rows, 'ALL entrapment')):
        if not g:
            continue
        acc = [r for r in g if r['tacc']]
        eqm = st.median([r['eq'] for r in g])
        tqm = st.median([r['tq'] for r in acc]) if acc else float('nan')
        eqa = st.median([r['eq'] for r in acc]) if acc else float('nan')
        print(f'{lbl:<26}{len(g):>5}{len(acc):>10} ({len(acc)/len(g)*100:4.1f}%)'
              f'{eqm:>11.2e}{tqm:>11.2e}{(eqa/tqm if acc else float("nan")):>8.1f}x')

    print(f"\nSAME PEAK? apex-RT agreement within {RT_SAME} min, over files where BOTH were scored")
    print(f"{'group':<26}{'pairs':>7}{'med files':>11}{'med |dRT| min':>15}{'% same peak':>13}")
    for g, lbl in ((near, 'near-copy'), (far, 'dissimilar')):
        w = [r for r in g if 'med_drt' in r]
        if not w:
            print(f'{lbl:<26}{0:>7}')
            continue
        print(f'{lbl:<26}{len(w):>7}{st.median([r["nshared"] for r in w]):>11.0f}'
              f'{st.median([r["med_drt"] for r in w]):>15.4f}'
              f'{st.mean([r["frac_same_peak"] for r in w])*100:>12.1f}%')

    w = sorted([r for r in near if 'med_drt' in r], key=lambda x: -x['ov'])[:12]
    if w:
        print(f"\nHighest-overlap near-copies with their target also accepted:")
        print(f"  {'ident':>6}{'fragOv':>7}{'ent q':>10}{'tgt q':>10}{'|dRT|':>8}{'same':>7}  "
              f"{'entrapment':<14}{'target':<14}")
        for r in w:
            print(f"  {r['id']:>6.3f}{r['ov']:>7.3f}{r['eq']:>10.2e}{r['tq']:>10.2e}"
                  f"{r['med_drt']:>8.4f}{r['frac_same_peak']*100:>6.0f}%  "
                  f"{r['eseq']:<14}{r['tseq']:<14}")
    json.dump(rows, open(sys.argv[1].replace('.json', '_pairs.json'), 'w'))


if __name__ == '__main__':
    main()
