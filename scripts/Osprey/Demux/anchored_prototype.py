"""Precursor-anchored extraction on the ZT Scan A1 slice: does fitting each library candidate's
fragments with the candidate's exact transmission profile, every other position solved blind,
separate real signal from noise better than the acquired spectra or the blind demux?

For library precursors whose m/z and predicted RT fall in the slice (the targets DIA-NN identified
on A1 in any arm, n random other targets, and n random entrapment precursors, which cannot be in
the sample and so are the known-false set), each of the top
library fragments is extracted (+/- TOL_PPM) from the encoded bins around the candidate in every
sweep near its predicted RT, and turned into a trace over sweeps by each method:
  own_bin    the acquired spectrum of the candidate's own encoded bin (what a plain search sees)
  matched    every acquired bin weighted by the transmission at the candidate's exact m/z (a matched
             filter; nothing removes other precursors' signal)
  blind5     the blind per-position solve summed over the 5 positions centered on the candidate's
             bin (what the centered:5 file carries)
  anchored   NNLS with the candidate's exact transmission column plus blind columns for every
             other position, the candidate's own position left to the anchor; Poisson refit
  anchored1  the same, with the positions within one of the candidate's also left to the anchor
Every method gets the same features and the same scoring: a linear discriminant, target against
entrapment, in two folds, reported as the targets passing 1% and 5% FDR estimated from the
entrapment. The anchored methods are also scored with one more feature, the share of the observed
signal near the candidate that the anchor explains (+share).

Usage: python anchored_prototype.py [--n 6000] [--workers 8] [--seed 1]
"""
import argparse
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from scipy.optimize import nnls
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ztscan_real import FIRST, KERNEL, STEP, read_slice, transmission_rows  # noqa: E402

MZML = r'D:\test\osprey-runs\ztscan\mzml\250814_ZTScan_100spd_A_1_A1.mzML'
LIB = r'D:\test\osprey-runs\ztscan\library\ztscan_carafe_lib.parquet'
RT_REPORT = r'D:\test\osprey-runs\ztscan\diann\C_plain\report.parquet'
REFERENCE = {'DIA-NN plain': RT_REPORT,
             'DIA-NN scanning (.wiff)': r'D:\test\osprey-runs\ztscan\diann\W_wiff_scanning\report.parquet'}
DEMUX_REPORT = r'D:\test\osprey-runs\ztscan\slices\diann\full_cs_centered5_A1\report.parquet'
OUT = r'D:\test\osprey-runs\ztscan\anchored'
CYCLES = (248, 372)     # the slice's sweeps (1-based cycle ids)
BINS = (70, 281)        # encoded bins read: the candidates' bins +/- (CONTEXT + REACH)
MZ_RANGE = (510.0, 690.0)
RT_RANGE = (4.3, 5.7)
TOL_PPM = 20.0
TOP = 6
HALF_WINDOW = 35        # sweeps each side of the predicted RT (95% of RT errors are within 0.52 min)
JOINT_HALF = 4          # sweeps each side of the apex for the joint fit
CONTEXT = 19            # blind positions each side of the candidate's bin
REACH = 9               # rows beyond the columns
FLOOR = 0.5             # ions: the Poisson weight floor
METHODS = ['own_bin', 'matched', 'blind5', 'anchored', 'anchored1']
# Encoded bin b's isolation target, as the spectra report it (exactly linear in b). FIRST in
# ztscan_real is the lower edge of bin 0, not its center.
TARGET0 = 393.439719644102
TARGET_STEP = (629.726233174212 - TARGET0) / 200


def bin_of(mz):
    """The encoded bin whose target is nearest mz, and mz's offset from that target."""
    b = int(round((mz - TARGET0) / TARGET_STEP))
    return b, mz - (TARGET0 + b * TARGET_STEP)

_state = {}


# ------------------------------------------------------------------------------------ data

def load_slice(workers):
    """The slice's MS2 peaks as one key array (spectrum * 1e4 + m/z, sorted), the ions' cumulative
    sum, and each sweep's time. Spectrum index = sweep * (bins read) + bin."""
    path = os.path.join(OUT, 'A1_slice.npz')
    if os.path.exists(path):
        # Memory-mapped .npy copies, so the workers share one copy of the pages.
        for name in ('key', 'csum', 'rt'):
            npy = os.path.join(OUT, 'A1_slice_%s.npy' % name)
            if not os.path.exists(npy):
                np.save(npy, np.load(path)[name])
        return tuple(np.load(os.path.join(OUT, 'A1_slice_%s.npy' % name), mmap_mode='r')
                     for name in ('key', 'csum', 'rt'))
    t0 = time.time()
    data = read_slice(MZML, CYCLES[0], CYCLES[1], BINS[0], BINS[1], CYCLES[0], CYCLES[1], workers)
    nb = BINS[1] - BINS[0] + 1
    keys, ions, rt = [], [], []
    for ci, c in enumerate(range(CYCLES[0], CYCLES[1] + 1)):
        ms2 = data[c][1]
        rt.append(ms2[0][2])
        for bi in range(nb):
            m, v = ms2[bi][0], ms2[bi][1].astype(np.float64)
            order = np.argsort(m, kind='stable')
            keys.append((ci * nb + bi) * 1e4 + m[order])
            ions.append(v[order])
    key = np.concatenate(keys)
    csum = np.concatenate([[0.0], np.cumsum(np.concatenate(ions))])
    rt = np.array(rt)
    os.makedirs(OUT, exist_ok=True)
    np.savez(path, key=key, csum=csum, rt=rt)
    print('read the slice in %.0f s: %d peaks' % (time.time() - t0, len(key)), flush=True)
    return key, csum, rt


def load_candidates(n, seed, rt_of_cycle):
    t0 = time.time()
    prec = pq.read_table(LIB, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Protein.Ids'],
                         filters=[('Precursor.Mz', '>=', MZ_RANGE[0]), ('Precursor.Mz', '<=', MZ_RANGE[1])])
    prec = prec.to_pandas().drop_duplicates('Precursor.Id').set_index('Precursor.Id')
    prec['entrapment'] = prec['Protein.Ids'].str.contains('_p_target', regex=False)

    # Library RT to run RT, from DIA-NN's plain identifications on A1: a median curve by library RT.
    rep = pd.read_parquet(RT_REPORT, columns=['Precursor.Id', 'RT', 'Q.Value'])
    rep = rep[rep['Q.Value'] <= 0.01].set_index('Precursor.Id')
    both = prec.join(rep[['RT']], rsuffix='.run', how='inner')
    lib_rt = both['RT'].values
    qs = np.quantile(lib_rt, np.linspace(0, 1, 41))
    mid = 0.5 * (qs[1:] + qs[:-1])
    med = [np.median(both['RT.run'].values[(lib_rt >= a) & (lib_rt <= b)]) for a, b in zip(qs[:-1], qs[1:])]
    prec['rt_pred'] = np.interp(prec['RT'].values, mid, med)
    resid = both['RT.run'].values - np.interp(lib_rt, mid, med)
    print('RT calibration from %d ids: residual SD %.3f min, 95%% within %.3f min' %
          (len(both), resid.std(), np.quantile(np.abs(resid), 0.95)), flush=True)

    # Only about 2% of the library's targets are in the sample, so the targets are every one DIA-NN
    # identified on A1 in any reference arm, plus n random others; the entrapment, n random, stands in
    # for the random (mostly false) targets, so e / t estimates the FDR as usual.
    inside = prec[(prec['rt_pred'] >= RT_RANGE[0]) & (prec['rt_pred'] <= RT_RANGE[1])]
    known = set()
    for path in list(REFERENCE.values()) + [DEMUX_REPORT]:
        rep = pd.read_parquet(path, columns=['Precursor.Id', 'Q.Value'])
        known |= set(rep.loc[rep['Q.Value'] <= 0.01, 'Precursor.Id'])
    targets = inside[~inside['entrapment']]
    identified = targets[targets.index.isin(known)]
    others = targets[~targets.index.isin(known)]
    trap = inside[inside['entrapment']]
    rng = np.random.default_rng(seed)
    parts = [identified,
             others.iloc[rng.choice(len(others), size=min(n, len(others)), replace=False)],
             trap.iloc[rng.choice(len(trap), size=min(n, len(trap)), replace=False)]]
    cand = pd.concat(parts).sort_index()
    print('in range: %d targets (%d identified by DIA-NN), %d entrapment; sampled %d + %d targets, %d entrapment' %
          (len(targets), len(identified), len(trap), len(parts[0]), len(parts[1]), len(parts[2])), flush=True)

    frag = pq.read_table(LIB, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                         filters=[('Precursor.Id', 'in', list(cand.index))]).to_pandas()
    frag = frag.sort_values(['Precursor.Id', 'Relative.Intensity'], ascending=[True, False], kind='stable')
    frag = frag.groupby('Precursor.Id', sort=True).head(TOP)
    tasks = []
    for pid, g in frag.groupby('Precursor.Id', sort=True):
        row = cand.loc[pid]
        ci0 = int(np.argmin(np.abs(rt_of_cycle - row['rt_pred'])))
        tasks.append((pid, float(row['Precursor.Mz']), ci0, float(row['rt_pred']),
                      g['Product.Mz'].values.astype(np.float64), g['Relative.Intensity'].values.astype(np.float64),
                      bool(row['entrapment'])))
    print('library read in %.0f s' % (time.time() - t0), flush=True)
    return tasks


# ------------------------------------------------------------------------------------ extraction

def init_worker(path):
    for name in ('key', 'csum', 'rt'):
        _state[name] = np.load(os.path.join(OUT, 'A1_slice_%s.npy' % name), mmap_mode='r')
    rows = np.genfromtxt(KERNEL, delimiter='\t', skip_header=1)
    off, val = rows[:, 0], np.nan_to_num(rows[:, 1])
    half = np.linspace(-STEP / 2, STEP / 2, 41)
    _state['off'], _state['val'] = off, val / np.interp(half, off, val).mean()
    rr = np.arange(-(CONTEXT + REACH), CONTEXT + REACH + 1)
    cc = np.arange(-CONTEXT, CONTEXT + 1)
    _state['rows_rel'], _state['cols_rel'] = rr, cc
    _state['blind'] = transmission_rows(rr * TARGET_STEP, cc * TARGET_STEP, 1)


def wnnls(m, y):
    """NNLS, then the Poisson-weighted refit with weights 1 / max(mu, FLOOR) from the first fit."""
    x = nnls(m, y, maxiter=50 * m.shape[1])[0]
    sw = 1.0 / np.sqrt(np.maximum(m @ x, FLOOR))
    return nnls(m * sw[:, None], y * sw, maxiter=50 * m.shape[1])[0]


def extract_candidate(task):
    pid, mz, ci0, rt_pred, fmz, fint, entrap = task
    key, csum, rt = _state['key'], _state['csum'], _state['rt']
    rr, cc, blind = _state['rows_rel'], _state['cols_rel'], _state['blind']
    nb = BINS[1] - BINS[0] + 1
    pbin, delta = bin_of(mz)
    sweeps = np.arange(max(0, ci0 - HALF_WINDOW), min(len(rt), ci0 + HALF_WINDOW + 1))
    bins = pbin + rr - BINS[0]
    spec = (sweeps[None, :] * nb + bins[:, None]).astype(np.float64)   # rows x sweeps
    anchor = np.interp(rr * TARGET_STEP - delta, _state['off'], _state['val'], left=0.0, right=0.0)
    near = np.abs(rr) <= REACH
    own = np.where(rr == 0)[0][0]
    m0 = np.column_stack([anchor, blind[:, cc != 0]])
    m1 = np.column_stack([anchor, blind[:, np.abs(cc) > 1]])
    five = np.abs(cc) <= 2
    nf, nt = len(fmz), len(sweeps)
    tr = {m: np.zeros((nf, nt)) for m in METHODS}
    explained = {m: np.zeros((nf, nt)) for m in ('anchored', 'anchored1')}
    observed = np.zeros((nf, nt))
    tol = TOL_PPM * 1e-6
    ys = []
    for f in range(nf):
        lo = np.searchsorted(key, (spec * 1e4 + fmz[f] * (1 - tol)).ravel())
        hi = np.searchsorted(key, (spec * 1e4 + fmz[f] * (1 + tol)).ravel(), side='right')
        y = (csum[hi] - csum[lo]).reshape(spec.shape)
        ys.append(y)
        tr['own_bin'][f] = y[own]
        tr['matched'][f] = anchor @ y / (anchor @ anchor)
        observed[f] = y[near].sum(axis=0)
        for t in range(nt):
            if observed[f, t] <= 0:
                continue
            yt = y[:, t]
            tr['blind5'][f, t] = wnnls(blind, yt)[five].sum()
            s0 = wnnls(m0, yt)[0]
            s1 = wnnls(m1, yt)[0]
            tr['anchored'][f, t], tr['anchored1'][f, t] = s0, s1
            explained['anchored'][f, t] = s0 * anchor[near].sum()
            explained['anchored1'][f, t] = s1 * anchor[near].sum()
    feats = {}
    for m in METHODS:
        feats[m] = features(tr[m], fint, rt[sweeps], rt_pred, explained.get(m), observed)
    feats['joint'] = feats['anchored1'][:5] + joint_features(ys, fint, anchor, m1[:, 1:], near, tr['anchored1'])
    return pid, entrap, feats


def deviance(y, mu):
    mu = np.maximum(mu, 0.05)
    pos = y > 0
    return 2.0 * (np.sum(y[pos] * np.log(y[pos] / mu[pos])) - np.sum(y - mu))


def joint_features(ys, fint, anchor, blind1, near, anchored_traces):
    """Near the apex of the per-fragment anchored trace, fit all fragments together: H1 has one
    elution value per sweep shared by every fragment in library proportion, through the candidate's
    exact transmission, plus each fragment's own blind columns (the positions within one of the
    candidate's left out); H0 is the same without the shared value. Returns log(1 + (D0 - D1)), the
    Poisson deviance drop summed over the sweeps (a likelihood ratio for "this precursor is here"),
    the share of the observed signal near the candidate that the shared value explains, and
    log(1 + the shared value's summed intensity)."""
    nf, nt = len(ys), ys[0].shape[1]
    total = anchored_traces.sum(axis=0)
    apex = int(np.argmax(np.convolve(total, [0.25, 0.5, 0.25], mode='same')))
    ts = range(max(0, apex - JOINT_HALF), min(nt, apex + JOINT_HALF + 1))
    rows, cols = blind1.shape
    lib = fint / fint.max()
    big = np.zeros((nf * rows, 1 + nf * cols))
    for f in range(nf):
        big[f * rows:(f + 1) * rows, 0] = lib[f] * anchor
        big[f * rows:(f + 1) * rows, 1 + f * cols:1 + (f + 1) * cols] = blind1
    drop, explained, observed, amount = 0.0, 0.0, 0.0, 0.0
    for t in ts:
        yt = np.concatenate([y[:, t] for y in ys])
        if yt.sum() <= 0:
            continue
        x1 = wnnls(big, yt)
        mu1 = big @ x1
        mu0 = np.concatenate([blind1 @ wnnls(blind1, y[:, t]) for y in ys])
        drop += deviance(yt, mu0) - deviance(yt, mu1)
        for f in range(nf):
            explained += lib[f] * x1[0] * anchor[near].sum()
            observed += ys[f][near, t].sum()
        amount += x1[0] * lib.sum()
    return [float(np.log1p(max(drop, 0.0))), float(explained / observed) if observed > 0 else 0.0,
            float(np.log1p(amount))]


def features(s, lib, rts, rt_pred, explained, observed):
    """Apex by the smoothed summed trace; then co-elution, library cosine, intensity, fragments seen,
    RT error, and (anchored only) the anchor's share of the observed signal near the candidate."""
    total = s.sum(axis=0)
    smooth = np.convolve(total, [0.25, 0.5, 0.25], mode='same')
    apex = int(np.argmax(smooth))
    w = slice(max(0, apex - 3), min(s.shape[1], apex + 4))
    sw = s[:, w]
    tw = sw.sum(axis=0)
    corrs = []
    for f in range(s.shape[0]):
        other = tw - sw[f]
        if sw[f].std() > 0 and other.std() > 0:
            corrs.append(np.corrcoef(sw[f], other)[0, 1])
        else:
            corrs.append(0.0)
    area = sw.sum(axis=1)
    a, b = np.sqrt(np.maximum(area, 0)), np.sqrt(lib)
    cos = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b))) if a.any() else 0.0
    out = [float(np.mean(corrs)), cos, float(np.log1p(max(area.sum(), 0))), float((area > 0.5).sum()),
           float(abs(rts[apex] - rt_pred))]
    if explained is not None:
        obs = observed[:, w].sum()
        out.append(float(explained[:, w].sum() / obs) if obs > 0 else 0.0)
    return out


# ------------------------------------------------------------------------------------ scoring

def passing(scores, entrap, fdr):
    order = np.argsort(-scores, kind='stable')
    e = np.cumsum(entrap[order])
    t = np.cumsum(~entrap[order])
    q = e / np.maximum(t, 1)
    q = np.minimum.accumulate(q[::-1])[::-1]
    return int(t[q <= fdr].max()) if (q <= fdr).any() else 0, order, q


def lda_scores(x, y, seed):
    rng = np.random.default_rng(seed)
    fold = rng.integers(0, 2, len(y))
    scores = np.zeros(len(y))
    for k in (0, 1):
        train, test = fold != k, fold == k
        mu, sd = x[train].mean(axis=0), x[train].std(axis=0) + 1e-12
        lda = LinearDiscriminantAnalysis().fit((x[train] - mu) / sd, ~y[train])
        scores[test] = lda.decision_function((x[test] - mu) / sd)
    return scores


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--n', type=int, default=5000)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--seed', type=int, default=1)
    args = ap.parse_args()
    key, csum, rt = load_slice(args.workers)
    tasks = load_candidates(args.n, args.seed, rt)
    t0 = time.time()
    results = []
    with ProcessPoolExecutor(max_workers=args.workers, initializer=init_worker,
                             initargs=(os.path.join(OUT, 'A1_slice.npz'),)) as ex:
        for k, r in enumerate(ex.map(extract_candidate, tasks, chunksize=32)):
            results.append(r)
            if (k + 1) % 2000 == 0:
                print('  %d of %d candidates, %.0f s' % (k + 1, len(tasks), time.time() - t0), flush=True)
    print('extracted %d candidates in %.0f s' % (len(results), time.time() - t0), flush=True)

    ids = np.array([r[0] for r in results])
    entrap = np.array([r[1] for r in results])
    refs = {}
    for name, path in REFERENCE.items():
        rep = pd.read_parquet(path, columns=['Precursor.Id', 'Q.Value'])
        refs[name] = set(rep.loc[rep['Q.Value'] <= 0.01, 'Precursor.Id'])
    rows = []
    for m in METHODS + ['joint']:
        x = np.array([r[2][m] for r in results])
        if m == 'joint':
            variants = [('anchored1 +joint', x), ('joint only', x[:, 4:])]
        else:
            variants = [(m, x[:, :5])] + ([(m + ' +share', x)] if x.shape[1] > 5 else [])
        for name, xv in variants:
            s = lda_scores(xv, entrap, args.seed)
            n1, order, q = passing(s, entrap, 0.01)
            n5, _, _ = passing(s, entrap, 0.05)
            hit = order[(q <= 0.01) & ~entrap[order]]
            overlap = {k: len(set(ids[hit]) & v) for k, v in refs.items()}
            rows.append((name, n1, n5, overlap))
    print('\n%d targets, %d entrapment; features: co-elution, library cosine, log intensity, fragments seen, RT error'
          % ((~entrap).sum(), entrap.sum()))
    print('%-18s %9s %9s   %s' % ('method', '1% FDR', '5% FDR', 'of the 1% targets, also found by'))
    for name, n1, n5, overlap in rows:
        print('%-18s %9d %9d   %s' % (name, n1, n5, ', '.join('%s %d' % kv for kv in overlap.items())))
    for name, v in refs.items():
        print('%s identified %d of the sampled targets' % (name, len(set(ids[~entrap]) & v)))
    out = pd.DataFrame({'id': ids, 'entrapment': entrap})
    for m in METHODS + ['joint']:
        x = np.array([r[2][m] for r in results])
        for j in range(x.shape[1]):
            out['%s_f%d' % (m, j)] = x[:, j]
    out.to_csv(os.path.join(OUT, 'features_seed%d_n%d.csv' % (args.seed, args.n)), index=False)


if __name__ == '__main__':
    main()
