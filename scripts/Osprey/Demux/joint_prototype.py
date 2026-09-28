"""Joint demultiplexing and centroiding of ZT Scan profile data (spec 5.4d) against the sequential forms, on the
precursors DIA-NN identified, scored by placement: the share of each precursor's top library fragments'
recovered signal near its apex that lands in its own encoded bin, and within +/- 1 bin.

The ZT Scan TOF profile is one exact grid, uniform in sqrt(m/z) (step 9.786595e-5) and shared by every spectrum,
so a fragment's profile samples line up across the encoded bins of a sweep. Per identified precursor, top-6
fragment and sweep near the apex, in a window of +/- HALF grid samples around the fragment m/z, with positions
(columns) the encoded bins around the precursor's own and rows those within the transmission's reach:

  vendor-channel      vendor centroids within +/- 10 ppm summed per row, then Poisson-weighted NNLS over the
                      positions (the current per-sweep channel solve)
  profile-channel     the same on the profile counts within +/- 10 ppm (all events, full areas)
  profile-sequential  Poisson-weighted NNLS at each grid sample separately (spec 5.4c), summed afterwards
  joint               one Poisson-weighted NNLS over (A kron B): unknowns beta[position, grid point], B a
                      Gaussian TOF peak (sigma SIGMA samples, unit area), so each peak's samples share one
                      position vector (spec 5.4d, without the L1)

Usage: python joint_prototype.py <profile.mzML> <vendor whole-run mzML> <DIA-NN report.parquet> <library.parquet>
       --cycles c0 c1 (1-based cycle ids of the profile dump) --mz lo hi (precursor m/z) [--workers N]
"""
import argparse
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from pyteomics import mzml
from scipy.optimize import nnls

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ztscan_real import ION, read_slice, transmission_rows  # noqa: E402

ROOT_STEP = 9.786595e-05
HALF = 16            # window half-width, grid samples
SIGMA = 1.35         # TOF peak sigma, grid samples (500-700 m/z)
CONTEXT = 12         # positions either side of the precursor's own bin
REACH = 9            # rows beyond the positions
TOP = 6
APEX = 2
CHANNEL_PPM = 10.0
SCORE_PPM = 20.0
FLOOR = 0.5
OFFSETS = np.arange(-3, 4)
METHODS = ['vendor-channel', 'profile-channel', 'profile-sequential', 'joint', 'joint-z2', 'joint-z2-relaxed']
ID_RE = re.compile(r'cycle=(\d+) experiment=(\d+)')


def read_profile(path):
    """{(cycle id, bin): (grid index array, ions array)} and the grid origin in sqrt(m/z)."""
    out, r0 = {}, None
    with mzml.MzML(path) as reader:
        for s in reader:
            if s.get('ms level') != 2:
                continue
            m = ID_RE.search(s['id'])
            c, b = int(m.group(1)), int(m.group(2)) - 2
            mz, it = s['m/z array'], s['intensity array']
            keep = it > 0
            mz, it = mz[keep], it[keep]
            if len(mz) == 0:
                continue
            root = np.sqrt(mz)
            if r0 is None:
                r0 = root.min()
            k = np.round((root - r0) / ROOT_STEP).astype(np.int64)
            order = np.argsort(k)
            out[(c, b)] = (k[order], it[order] / ION)
    return out, r0


def wnnls(M, y):
    x = nnls(M, y, maxiter=50 * M.shape[1])[0]
    w = 1.0 / np.sqrt(np.maximum(M @ x, FLOOR))
    return nnls(M * w[:, None], y * w, maxiter=50 * M.shape[1])[0]


def wnnls_z(M, y, z, relaxed):
    """Poisson-weighted NNLS with a per-column lasso of z standard deviations of the column's score,
    c_j = z sqrt((M^T W M)_jj), weights from the unpenalized fit. Exact through the Cholesky factor of the
    weighted Gram: beta^T G beta - 2 (b - c)^T beta = ||R beta - R^-T (b - c)||^2 + const. Relaxed: the
    kept columns refitted without the penalty."""
    x = nnls(M, y, maxiter=50 * M.shape[1])[0]
    w = 1.0 / np.maximum(M @ x, FLOOR)
    G = M.T @ (M * w[:, None])
    b = M.T @ (w * y)
    G = G + 1e-9 * np.trace(G) / len(G) * np.eye(len(G))
    R = np.linalg.cholesky(G).T                     # G = R^T R
    c = z * np.sqrt(np.diag(G))
    d = np.linalg.solve(R.T, b - c)
    beta = nnls(R, d, maxiter=50 * len(G))[0]
    if relaxed and beta.any():
        keep = beta > 0
        Rk = np.linalg.cholesky(G[np.ix_(keep, keep)]).T
        dk = np.linalg.solve(Rk.T, b[keep])
        beta = np.zeros_like(beta)
        beta[keep] = nnls(Rk, dk, maxiter=50 * keep.sum())[0]
    return beta


def gaussian_basis(n):
    p = np.arange(n)
    B = np.exp(-0.5 * ((p[:, None] - p[None, :]) / SIGMA) ** 2)
    return B / B.sum(axis=0, keepdims=True)  # unit area per grid point (window edges truncate)


def score_precursor(task):
    (fragments, cycles, pb, rows, cols, A, window_profile, window_vendor, r0, active) = task
    shares = {m: np.zeros(len(OFFSETS)) for m in METHODS}
    own_cols = {d: int(np.where(cols == pb + d)[0][0]) for d in OFFSETS}
    B_full = gaussian_basis(2 * HALF + 1)
    for fm in fragments:
        kc = int(round((np.sqrt(fm) - r0) / ROOT_STEP))
        ks = np.arange(kc - HALF, kc + HALF + 1)
        mz_of = (r0 + ks * ROOT_STEP) ** 2
        in_channel = np.abs(mz_of - fm) / fm * 1e6 <= CHANNEL_PPM
        in_score = np.abs(mz_of - fm) / fm * 1e6 <= SCORE_PPM
        for c in cycles:
            Y = window_profile(c, rows, ks)            # rows x samples, ions
            if Y.sum() == 0:
                continue
            V = window_vendor(c, rows, fm)             # rows, ions within CHANNEL_PPM
            used = np.array([np.any((A[:, j] > 0) & (Y.sum(axis=1) > 0)) for j in range(len(cols))])
            if not used.any():
                continue
            Au = A[:, used]
            idx = np.where(used)[0]

            def add(method, x_cols):
                for d, j in own_cols.items():
                    hit = np.where(idx == j)[0]
                    if len(hit):
                        shares[method][d + 3] += x_cols[hit[0]]

            if V.sum() > 0 and 'vendor-channel' in active:
                add('vendor-channel', wnnls(Au, V))
            if 'profile-channel' in active:
                add('profile-channel', wnnls(Au, Y[:, in_channel].sum(axis=1)))
            if 'profile-sequential' in active:
                seq = np.zeros(len(idx))
                for p in np.where(in_score)[0]:
                    if Y[:, p].sum() > 0:
                        seq += wnnls(Au, Y[:, p])
                add('profile-sequential', seq)
            # Joint: grid points where any row has signal within 2 samples.
            live = np.convolve((Y.sum(axis=0) > 0).astype(float), np.ones(5), mode='same') > 0
            q = np.where(live)[0]
            M = np.kron(Au, B_full[:, q])              # (rows*samples) x (positions*q)
            for name, solve in (('joint', lambda: wnnls(M, Y.ravel())),
                                ('joint-z2', lambda: wnnls_z(M, Y.ravel(), 2.0, False)),
                                ('joint-z2-relaxed', lambda: wnnls_z(M, Y.ravel(), 2.0, True))):
                if name in active:
                    beta = solve().reshape(len(idx), len(q))
                    add(name, beta[:, in_score[q]].sum(axis=1))
    return shares


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('profile')
    ap.add_argument('vendor')
    ap.add_argument('report')
    ap.add_argument('library')
    ap.add_argument('--cycles', type=int, nargs=2, required=True)
    ap.add_argument('--mz', type=float, nargs=2, required=True)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--methods', default=','.join(METHODS), help='comma-separated subset of ' + ', '.join(METHODS))
    args = ap.parse_args()
    active = [m for m in METHODS if m in args.methods.split(',')]
    t0 = time.time()
    profile, r0 = read_profile(args.profile)
    bins = sorted({b for _, b in profile})
    print('profile: %d spectra, bins %d-%d, %.0f s' % (len(profile), bins[0], bins[-1], time.time() - t0), flush=True)
    c0, c1 = args.cycles
    data = read_slice(args.vendor, c0, c1, bins[0], bins[-1], c0, c1, args.workers)
    targets = np.array([data[c0][1][b - bins[0]][3] for b in bins])
    rts = {c: data[c][1][0][2] for c in range(c0, c1 + 1)}
    print('vendor: cycles %d-%d read, %.0f s' % (c0, c1, time.time() - t0), flush=True)

    rep = pd.read_parquet(args.report, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Q.Value', 'Protein.Ids'])
    rep = rep[(rep['Q.Value'] <= 0.01) & ~rep['Protein.Ids'].str.contains('_p_target', regex=False)]
    rep = rep.drop_duplicates('Precursor.Id')
    rt_lo, rt_hi = rts[c0 + APEX], rts[c1 - APEX]
    rep = rep[rep['Precursor.Mz'].between(*args.mz) & rep['RT'].between(rt_lo, rt_hi)]
    if args.limit:
        rep = rep.head(args.limit)
    frag = pq.read_table(args.library, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                         filters=[('Precursor.Id', 'in', list(rep['Precursor.Id']))]).to_pandas()
    frag = frag.sort_values(['Precursor.Id', 'Relative.Intensity'], ascending=[True, False], kind='stable')
    fr = {pid: g['Product.Mz'].values for pid, g in frag.groupby('Precursor.Id', sort=True).head(TOP).groupby('Precursor.Id')}
    print('%d identified precursors in m/z %.0f-%.0f, RT %.2f-%.2f' % (len(rep), *args.mz, rt_lo, rt_hi), flush=True)

    b_lo, b_hi = bins[0], bins[-1]
    tasks = []
    cyc = np.array(sorted(rts))
    rt_arr = np.array([rts[c] for c in cyc])
    for _, r in rep.iterrows():
        pb = bins[int(np.argmin(np.abs(targets - r['Precursor.Mz'])))]
        cols = np.arange(pb - CONTEXT, pb + CONTEXT + 1)
        rows = np.arange(cols[0] - REACH, cols[-1] + REACH + 1)
        if rows[0] < b_lo or rows[-1] > b_hi:
            continue
        ci = int(np.argmin(np.abs(rt_arr - r['RT'])))
        cycles = cyc[max(0, ci - APEX):ci + APEX + 1]
        A = transmission_rows(targets[rows - b_lo], targets[cols - b_lo], 1)
        # Pre-extract the data this precursor needs, so each task is self-contained.
        prof = {(c, b): profile.get((c, b)) for c in cycles for b in rows}
        vend = {(c, b): data[c][1][b - b_lo][:2] for c in cycles for b in rows}
        tasks.append((fr.get(r['Precursor.Id'], []), cycles, pb, rows, cols, A, prof, vend))
    print('%d precursors scored' % len(tasks), flush=True)

    total = {m: np.zeros(len(OFFSETS)) for m in METHODS}
    per = {m: [] for m in METHODS}
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        for k, shares in enumerate(ex.map(run_task, [(t, r0, set(active)) for t in tasks])):
            for m in active:
                total[m] += shares[m]
                if shares[m].sum() > 0:
                    per[m].append(shares[m][3] / shares[m].sum())
            if (k + 1) % 50 == 0:
                print('  %d/%d, %.0f s' % (k + 1, len(tasks), time.time() - t0), flush=True)
    print('\nplacement of the top-%d fragments near the apex, by bin offset from the precursor\'s own bin' % TOP)
    print('%-20s %s   own  +/-1  median own   recovered' % ('method', ' '.join('%6d' % d for d in OFFSETS)))
    for m in active:
        s = total[m] / max(total[m].sum(), 1e-30)
        print('%-20s %s  %.2f  %.2f     %.2f     %10.0f' % (m, ' '.join('%6.3f' % x for x in s), s[3], s[2:5].sum(),
                                                            np.median(per[m]) if per[m] else float('nan'), total[m].sum()))
    print('%.0f s' % (time.time() - t0))


def run_task(args):
    (fragments, cycles, pb, rows, cols, A, prof, vend), r0, active = args

    def window_profile(c, rws, ks):
        Y = np.zeros((len(rws), len(ks)))
        for i, b in enumerate(rws):
            p = prof.get((c, b))
            if p is None:
                continue
            k, v = p
            a, e = np.searchsorted(k, [ks[0], ks[-1] + 1])
            Y[i, k[a:e] - ks[0]] = v[a:e]
        return Y

    def window_vendor(c, rws, fm):
        out = np.zeros(len(rws))
        tol = fm * CHANNEL_PPM * 1e-6
        for i, b in enumerate(rws):
            mz, ions = vend[(c, b)]
            sel = np.abs(mz - fm) <= tol
            out[i] = ions[sel].sum()
        return out

    return score_precursor((fragments, cycles, pb, rows, cols, A, window_profile, window_vendor, r0, active))


if __name__ == '__main__':
    main()
