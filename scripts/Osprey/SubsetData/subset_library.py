"""Choose the library precursors for an m/z x RT rectangle and write the subset .tsv library.

Detected precursors (from a full-run blib) are kept when their observed RT is inside the
slice. Undetected precursors are kept when their library RT, mapped to observed RT by a
binned-median fit over the detections, lands inside the slice. Rows are copied verbatim from
the source library except, with --synthetic-proteins, ProteinID.

A full-run detection is matched to a library precursor by (stripped sequence, charge, m/z to
0.01). Do not match on m/z and charge alone: different peptides collide often enough to label
a third of a window "detected" and to wreck the RT fit (resid SD 3 min instead of 0.18).

Usage: python subset_library.py FULL.blib LIB.tsv OUT.tsv --mz-lo L --mz-hi H --rt-min A --rt-max B
       [--undetected-max N] [--synthetic-proteins K] [--manifest OUT_MANIFEST.tsv]
"""
import argparse
import re
import sqlite3
import zlib

import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('blib')
    ap.add_argument('lib')
    ap.add_argument('out')
    ap.add_argument('--mz-lo', type=float, required=True)
    ap.add_argument('--mz-hi', type=float, required=True)
    ap.add_argument('--rt-min', type=float, required=True)
    ap.add_argument('--rt-max', type=float, required=True)
    ap.add_argument('--undetected-max', type=int, default=-1,
                    help='cap on undetected precursors, thinned deterministically')
    ap.add_argument('--synthetic-proteins', type=int, default=0,
                    help='regroup peptides into synthetic proteins of this many peptides (0 = real accessions)')
    ap.add_argument('--shared-every', type=int, default=8,
                    help='with --synthetic-proteins: every Nth group shares its first peptide with the next')
    ap.add_argument('--manifest', default=None, help='TSV of the chosen precursors with a detected flag')
    a = ap.parse_args()

    c = sqlite3.connect(a.blib)
    det = {}
    for seq, mz, z, rt in c.execute(
            'select peptideSeq, precursorMZ, precursorCharge, retentionTime from RefSpectra'):
        det[(seq, int(z), round(mz, 2))] = rt

    def det_key(key, mz):
        return (re.sub(r'\[.*?\]', '', key[0]).strip('_'), key[1], round(mz, 2))

    # Unique precursors in library order
    prec = {}
    with open(a.lib, 'r', encoding='utf-8') as f:
        hdr = f.readline().rstrip('\n').split('\t')
        ci = {h: i for i, h in enumerate(hdr)}
        for line in f:
            p = line.rstrip('\n').split('\t')
            key = (p[ci['ModifiedPeptide']], int(p[ci['PrecursorCharge']]))
            if key not in prec:
                prec[key] = (float(p[ci['PrecursorMz']]), float(p[ci['Tr_recalibrated']]))

    # Binned-median library RT -> observed RT over all detections
    xs, ys = [], []
    for key, (mz, lrt) in prec.items():
        rt = det.get(det_key(key, mz))
        if rt is not None:
            xs.append(lrt)
            ys.append(rt)
    xs, ys = np.array(xs), np.array(ys)
    edges = np.arange(np.floor(xs.min()), np.ceil(xs.max()) + 0.5, 0.5)
    mids, meds = [], []
    for lo, hi in zip(edges[:-1], edges[1:]):
        sel = (xs >= lo) & (xs < hi)
        if sel.sum() >= 20:
            mids.append((lo + hi) / 2)
            meds.append(np.median(ys[sel]))

    def predict(lrt):
        return float(np.interp(lrt, mids, meds))

    resid = ys - np.array([predict(x) for x in xs])
    print('library RT fit over %d detections: resid sd %.3f min, p90 abs %.3f min'
          % (len(xs), resid.std(), np.percentile(abs(resid), 90)))

    chosen_det, chosen_undet = [], []
    for key, (mz, lrt) in prec.items():
        if not (a.mz_lo <= mz <= a.mz_hi):
            continue
        rt = det.get(det_key(key, mz))
        if rt is not None:
            if a.rt_min <= rt <= a.rt_max:
                chosen_det.append((key, rt))
        else:
            prt = predict(lrt)
            if a.rt_min <= prt <= a.rt_max:
                chosen_undet.append((key, prt))
    chosen_undet.sort(key=lambda e: (e[0][0], e[0][1]))
    if 0 <= a.undetected_max < len(chosen_undet):
        step = len(chosen_undet) / float(a.undetected_max)
        chosen_undet = [chosen_undet[int(i * step)] for i in range(a.undetected_max)]
    keep = {e[0] for e in chosen_det} | {e[0] for e in chosen_undet}

    # Synthetic proteins: a single isolation window almost never holds two peptides of one
    # real protein, so the >=2-peptide protein paths (second-pass FDR stratum, parsimony,
    # reconciliation) would never run.
    new_prot = {}
    if a.synthetic_proteins > 0:
        peps = sorted({k[0].replace('_', '') for k in keep}, key=lambda s: (zlib.crc32(s.encode('utf-8')), s))
        n_groups = (len(peps) + a.synthetic_proteins - 1) // a.synthetic_proteins

        def acc(g):
            return 'sp|SUB%03d|SUB%03d_SUBSET' % (g + 1, g + 1)

        for i, pep in enumerate(peps):
            g = i // a.synthetic_proteins
            ids = [acc(g)]
            if a.shared_every > 0 and i % a.synthetic_proteins == 0 and g % a.shared_every == 0 and g + 1 < n_groups:
                ids.append(acc(g + 1))
            new_prot[pep] = ';'.join(ids)
        print('synthetic proteins: %d groups over %d peptides' % (n_groups, len(peps)))

    n_rows = 0
    with open(a.lib, 'r', encoding='utf-8') as f, open(a.out, 'w', encoding='utf-8', newline='\n') as w:
        w.write(f.readline())
        for line in f:
            cols = line.rstrip('\n').split('\t')
            k = (cols[ci['ModifiedPeptide']], int(cols[ci['PrecursorCharge']]))
            if k not in keep:
                continue
            if new_prot:
                cols[ci['ProteinID']] = new_prot[k[0].replace('_', '')]
                line = '\t'.join(cols) + '\n'
            w.write(line)
            n_rows += 1
    if a.manifest:
        with open(a.manifest, 'w', newline='\n') as w:
            w.write('ModifiedPeptide\tPrecursorCharge\tDetectedInFullRun\tRt\n')
            for (k, rt) in sorted(chosen_det):
                w.write('%s\t%d\t1\t%.3f\n' % (k[0], k[1], rt))
            for (k, rt) in sorted(chosen_undet):
                w.write('%s\t%d\t0\t%.3f\n' % (k[0], k[1], rt))
    print('detected %d, undetected %d, library rows %d' % (len(chosen_det), len(chosen_undet), n_rows))


if __name__ == '__main__':
    main()
