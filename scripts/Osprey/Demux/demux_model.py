"""Model of overlapping-window DIA demultiplexing on synthetic peptides, scored on quantitation.

The same target peptides are acquired as an Orbitrap Eclipse staggered method (12 Th windows,
k = 2) or as a SCIEX ZT Scan method (an ~11 Th transmission stepped 1.18 Th, k ~ 16), in two
samples (A and B) with known fold changes for the targets and Poisson counting noise. The
targets sit among many more co-eluting, co-isolated background peptides, sized to give the
peak density of the real spectra; the background does not change between samples.

Demultiplexing is per product-ion channel, y = A x, x >= 0:
  none        the acquired spectra as they are (no demux): the baseline;
  per-time    one NNLS per channel per time point: per sweep for ZT Scan; for staggered, the
              other windows interpolated (makima) to each spectrum's time first (spec 4.4);
  time-model  one NNLS per channel per block of time: each bin's intensity a nonnegative
              combination of hat functions on a time grid, fitted to the acquired times with a
              second-difference roughness penalty (spec 4.3).
Only the channels of the targets' top fragments are simulated and solved. Channels are solved
independently, so that is exact for every variant here.

Usage: python demux_model.py --scheme ztscan|staggered [--out results.json] [options]
"""
import argparse
import json
import os
import pickle
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from pyteomics import fasta, mass, parser
from scipy.interpolate import Akima1DInterpolator
from scipy.optimize import lsq_linear, nnls
from scipy.stats import exponnorm

from demux_roots import DATA_ROOT

PROTON = 1.007276
WATER = 18.010565
AA = dict(mass.std_aa_mass)
AA['C'] += 57.021464  # carbamidomethyl
ALLOWED = set('ACDEFGHIKLMNPQRSTVWY')
FRAG_LO, FRAG_HI = 150.0, 1400.0

FASTA = os.path.join(DATA_ROOT, 'ZenoTOF8600-ZTScan', 'uniprot_human_march2026_yeastENO1_contam_ADpeps.fasta')
KERNEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kernels', 'A1_rt3-8.profile.tsv')


# ------------------------------------------------------------------------------------ peptides

def candidates(path, mz_lo, mz_hi):
    """Tryptic peptides (no missed cleavages, 7-25 residues) at charge 2 or 3 in [mz_lo, mz_hi)."""
    seqs = set()
    for _, protein in fasta.read(path):
        for pep in parser.cleave(protein, parser.expasy_rules['trypsin'], 0, min_length=7):
            if len(pep) <= 25 and set(pep) <= ALLOWED:
                seqs.add(pep)
    out = []
    for seq in sorted(seqs):
        m = sum(AA[a] for a in seq) + WATER
        for z in (2, 3):
            mz = (m + z * PROTON) / z
            if mz_lo <= mz < mz_hi:
                out.append((seq, z, mz))
    return out


def fragment_mzs(seq, z):
    """b (from b2) and y ions at 1+, and at 2+ for 3+ precursors, within the fragment range."""
    cum = np.cumsum([AA[a] for a in seq])
    total = cum[-1]
    out = []
    for i in range(1, len(seq)):
        b = cum[i - 1] + PROTON
        y = total - cum[i - 1] + WATER + PROTON
        ions = [y] + ([b] if i >= 2 else [])
        if z >= 3:
            ions += [(ion + PROTON) / 2 for ion in ions]
        out += [ion for ion in ions if FRAG_LO <= ion <= FRAG_HI]
    return np.array(out)


class Peptides:
    """Peptides as arrays: precursor m/z, elution (EMG, unit height), abundance, fold change, and
    each one's fragments (m/z and intensity relative to its base fragment)."""

    def __init__(self, cands, n, rt_lo, rt_hi, fwhm, ions_lo, ions_hi, top, rng, fold_changes):
        pick = rng.choice(len(cands), size=n, replace=False)
        self.seq = [cands[k][0] for k in pick]
        self.z = np.array([cands[k][1] for k in pick])
        self.mz = np.array([cands[k][2] for k in pick])
        self.apex = rng.uniform(rt_lo, rt_hi, n)
        self.sigma = fwhm * np.exp(rng.normal(0, 0.2, n)) / 2.3548
        self.k = rng.uniform(0.05, 1.0, n)  # EMG tau / sigma
        self.base = 10 ** rng.uniform(ions_lo, ions_hi, n)
        self.fc = rng.choice(fold_changes, size=n) if fold_changes is not None else np.zeros(n)
        xs = np.linspace(-6, 12, 3601)
        self.loc = np.empty(n)
        self.norm = np.empty(n)
        for i in range(n):
            pdf = exponnorm.pdf(xs, self.k[i])
            self.loc[i] = self.apex[i] - xs[np.argmax(pdf)] * self.sigma[i]
            self.norm[i] = pdf.max()
        self.frag_mz, self.frag_rel = [], []
        for i in range(n):
            fm = fragment_mzs(self.seq[i], self.z[i])
            rel = np.exp(rng.normal(0, 1, len(fm)))
            order = np.argsort(-rel, kind='stable')[:top]
            self.frag_mz.append(fm[order])
            self.frag_rel.append(rel[order] / rel[order[0]])

    def __len__(self):
        return len(self.mz)

    def elution(self, i, t):
        return exponnorm.pdf((t - self.loc[i]) / self.sigma[i], self.k[i]) / self.norm[i]

    def amount(self, i, sample):
        return self.base[i] * (2.0 ** self.fc[i] if sample == 1 else 1.0)


# ------------------------------------------------------------------------------------- schemes

class Scheme:
    """Isolation events (rows of A) at their acquisition times, and the narrow bins (columns).

    event_t: acquisition time of each event. trans(mz): (events x len(mz)) transmission.
    A: (events x bins) transmission averaged over each bin. bin_output[j]: the events whose
    times are the output times of bin j. nodemux(mz): the events a search without demux reads
    for a precursor at mz.
    """

    def finish(self, subbins=1):
        """A over the output bins, and A_solve over subbins equal parts of each bin: the columns the
        solve uses, summed back into the output bins afterwards."""
        self.A = self.bin_average(self.bin_lo, self.bin_hi)
        self.subbins = subbins
        width = (self.bin_hi - self.bin_lo) / subbins
        lo = (self.bin_lo[:, None] + width[:, None] * np.arange(subbins)).ravel()
        self.A_solve = self.bin_average(lo, lo + np.repeat(width, subbins))

    def bin_average(self, lo, hi, points=21):
        grid = lo[:, None] + (np.arange(points) + 0.5) / points * (hi - lo)[:, None]
        return self.trans(grid.ravel()).reshape(len(self.event_t), len(lo), points).mean(axis=2)

    def to_bins(self, x):
        return x.reshape(-1, self.subbins).sum(axis=1)

    def bin_of(self, mz):
        return int(np.searchsorted(self.bin_hi, mz, side='right'))


class ZtScan(Scheme):
    STEP, FIRST, NBINS = 1.181866, 392.760634, 429
    CYCLE, DT, MS1 = 0.971, 0.00201, 0.10

    def __init__(self, mz_lo, mz_hi, t_lo, t_hi, kernel=KERNEL, subbins=1, sim_scale=1.0):
        self.scale = 1.0
        rows = np.genfromtxt(kernel, delimiter='\t', skip_header=1)
        self.k_off = rows[:, 0]
        vals = np.nan_to_num(rows[:, 1])
        # Scale so a precursor at the center of its own encoded bin is transmitted at 1 on
        # average over the bin: the narrow-window reference the demux output is compared with.
        half = np.linspace(-self.STEP / 2, self.STEP / 2, 41)
        self.k_val = vals / np.interp(half, self.k_off, vals).mean()
        centers = self.FIRST + self.STEP * (np.arange(self.NBINS) + 0.5)
        sel = np.nonzero((centers >= mz_lo - 14) & (centers <= mz_hi + 14))[0]
        self.bin_lo = centers[sel] - self.STEP / 2
        self.bin_hi = centers[sel] + self.STEP / 2
        cycles = np.arange(int(np.floor(t_lo / self.CYCLE)), int(np.ceil(t_hi / self.CYCLE)))
        self.event_t = np.array([c * self.CYCLE + self.MS1 + b * self.DT for c in cycles for b in sel])
        self.event_center = np.tile(centers[sel], len(cycles))
        self.event_bin = np.tile(np.arange(len(sel)), len(cycles))
        n = len(sel)
        self.cycles = [np.arange(ci * n, (ci + 1) * n) for ci in range(len(cycles))]
        self.bin_output = [np.arange(j, len(self.event_t), n) for j in range(n)]
        self.grid_default = cycles * self.CYCLE + self.MS1 + sel.mean() * self.DT
        self.finish(subbins)
        # A is built from the nominal transmission; the simulated one may be wider or narrower,
        # to test a misspecified kernel.
        self.scale = sim_scale

    def trans(self, mz):
        return np.interp((self.event_center[:, None] - np.asarray(mz)[None, :]) / self.scale, self.k_off,
                         self.k_val, left=0.0, right=0.0)

    def nodemux(self, mz):
        return self.bin_output[self.bin_of(mz)]


class Staggered(Scheme):
    WIDTH, LO = 12.0, 394.0
    CYCLE, MS1 = 5.446, 0.06

    def __init__(self, mz_lo, mz_hi, t_lo, t_hi, edge=0.3, subbins=1):
        self.edge = edge
        lows = [self.LO + self.WIDTH * k for k in range(51)] + [self.LO + 6 + self.WIDTH * k for k in range(50)]
        dt = (self.CYCLE - self.MS1) / len(lows)
        sel = [m for m, lo in enumerate(lows) if lo < mz_hi + 18 and lo + self.WIDTH > mz_lo - 18]
        self.win_lo = np.array([lows[m] for m in sel])
        self.win_hi = self.win_lo + self.WIDTH
        bounds = np.unique(np.concatenate([self.win_lo, self.win_hi]))
        self.bin_lo, self.bin_hi = bounds[:-1], bounds[1:]
        cycles = np.arange(int(np.floor(t_lo / self.CYCLE)), int(np.ceil(t_hi / self.CYCLE)))
        ev = [(c * self.CYCLE + self.MS1 + m * dt, w) for c in cycles for w, m in enumerate(sel)]
        ev.sort()
        self.event_t = np.array([e[0] for e in ev])
        self.event_window = np.array([e[1] for e in ev])
        self.event_lo = self.win_lo[self.event_window]
        self.event_hi = self.win_hi[self.event_window]
        self.window_events = [np.nonzero(self.event_window == w)[0] for w in range(len(sel))]
        self.bin_output = []
        for j in range(len(self.bin_lo)):
            covering = (self.event_lo <= self.bin_lo[j] + 1e-9) & (self.event_hi >= self.bin_hi[j] - 1e-9)
            self.bin_output.append(np.nonzero(covering)[0])
        self.grid_default = np.arange(t_lo, t_hi + 1e-9, self.CYCLE / 4)
        self.finish(subbins)
        self.Aw = np.array([self.A_solve[self.window_events[w][0]] for w in range(len(sel))])
        self.Aw_bins = np.array([self.A[self.window_events[w][0]] for w in range(len(sel))])

    def trans(self, mz):
        mz = np.asarray(mz)[None, :]
        e = self.edge
        up = np.clip((mz - (self.event_lo[:, None] - e / 2)) / e, 0, 1)
        down = np.clip(((self.event_hi[:, None] + e / 2) - mz) / e, 0, 1)
        return up * down

    def nodemux(self, mz):
        return np.nonzero((self.event_lo <= mz) & (self.event_hi > mz))[0]


# ---------------------------------------------------------------------------------- simulation

def build_channels(targets, top_score, tol_ppm):
    """Channel centers from the targets' top fragments, merged within the tolerance, and each
    target fragment's channel."""
    allm = np.sort(np.concatenate([targets.frag_mz[i][:top_score] for i in range(len(targets))]))
    centers, group = [], [allm[0]]
    for m in allm[1:]:
        if m - group[0] <= group[0] * tol_ppm * 1e-6:
            group.append(m)
        else:
            centers.append(np.mean(group))
            group = [m]
    centers.append(np.mean(group))
    centers = np.array(centers)
    tchan = [np.array([nearest(centers, m) for m in targets.frag_mz[i][:top_score]]) for i in range(len(targets))]
    return centers, tchan


def nearest(centers, m):
    k = int(np.searchsorted(centers, m))
    if k == len(centers) or (k > 0 and m - centers[k - 1] < centers[k] - m):
        k -= 1
    return k


def members(pepsets, centers, tol_ppm):
    """For each channel, the (set, peptide, relative intensity) of every fragment within tolerance."""
    out = [[] for _ in centers]
    for s, peps in enumerate(pepsets):
        for i in range(len(peps)):
            for m, rel in zip(peps.frag_mz[i], peps.frag_rel[i]):
                k = nearest(centers, m)
                if abs(m - centers[k]) <= centers[k] * tol_ppm * 1e-6:
                    out[k].append((s, i, rel))
    return out


def simulate(scheme, pepsets, memb, sample, rng, floor, noiseless=False):
    """Poisson counts per event and channel (or their expectation, noiseless)."""
    lam = np.zeros((len(scheme.event_t), len(memb)))
    cache = {}
    for c, lst in enumerate(memb):
        for s, i, rel in lst:
            key = (s, i)
            if key not in cache:
                peps = pepsets[s]
                cache[key] = scheme.trans([peps.mz[i]])[:, 0] * peps.elution(i, scheme.event_t) * peps.amount(i, sample)
            lam[:, c] += cache[key] * rel
    y = lam if noiseless else rng.poisson(lam).astype(float)
    if floor > 0:
        y[y < floor] = 0.0
    return y


def peaks_per_event(scheme, pepsets, mz_mid, sample=0):
    """Expected nonzero fragment peaks in the event nearest the middle of the run among those
    transmitting mz_mid."""
    covering = np.nonzero(scheme.trans([mz_mid])[:, 0] > 0.5)[0]
    e = int(covering[np.argmin(np.abs(scheme.event_t[covering] - scheme.event_t.mean()))])
    total = 0.0
    for peps in pepsets:
        tr = scheme.trans(peps.mz)[e]
        for i in np.nonzero(tr > 0)[0]:
            lam = tr[i] * peps.elution(i, scheme.event_t[e]) * peps.amount(i, sample) * peps.frag_rel[i]
            total += (1 - np.exp(-lam)).sum()
    return total


# ------------------------------------------------------------------------------------- solvers

def solve(A, y):
    """NNLS on the rows and columns a channel's nonzero measurements reach."""
    x = np.zeros(A.shape[1])
    nz = y > 0
    if not nz.any():
        return x
    cols = np.nonzero((A[nz] > 1e-9).any(axis=0))[0]
    rows = np.nonzero((A[:, cols] > 1e-9).any(axis=1))[0]
    x[cols] = nnls_robust(A[np.ix_(rows, cols)], y[rows])
    return x


def solve_weighted(A, y, sqrt_w):
    """solve() with each row scaled by sqrt_w, on the same restricted rows and columns."""
    x = np.zeros(A.shape[1])
    nz = y > 0
    if not nz.any():
        return x
    cols = np.nonzero((A[nz] > 1e-9).any(axis=0))[0]
    rows = np.nonzero((A[:, cols] > 1e-9).any(axis=1))[0]
    x[cols] = nnls_robust(A[np.ix_(rows, cols)] * sqrt_w[rows, None], y[rows] * sqrt_w[rows])
    return x


def nnls_robust(M, b):
    try:
        return nnls(M, b, maxiter=50 * M.shape[1])[0]
    except RuntimeError:
        return lsq_linear(M, b, bounds=(0, np.inf), method='bvls').x


_W = {}


def _init(state):
    _W.update(state)


def per_sweep_channel(c):
    """ZT Scan: one NNLS per sweep for channel c. Returns {bin: values over cycles}."""
    A, Y, cycles, S = _W['A'], _W['Y'], _W['cycles'], _W['S']
    weighted, pool = _W.get('weighted', False), _W.get('pool', 0)
    out = {}
    ys = [Y[ev, c] for ev in cycles]
    for ci, ev in enumerate(cycles):
        y = ys[ci]
        if not y.any():
            continue
        Ac = A[ev]
        if pool:
            # The active positions from the sweeps within pool of this one, summed (all their
            # ions); this sweep's amplitudes then solved on those positions only.
            pooled = np.sum(ys[max(0, ci - pool):ci + pool + 1], axis=0)
            xp = solve(Ac, pooled)
            if _W.get('union', False):
                # Keep this sweep's own positions too, so a source the pooled solve misses keeps its bin.
                xp = xp + solve(Ac, y)
            support = np.nonzero(xp > 1e-9 * max(xp.max(), 1e-300))[0]
            x = np.zeros(Ac.shape[1])
            if len(support):
                x[support] = solve(Ac[:, support], y)
                if weighted:
                    w = 1.0 / np.sqrt(np.maximum(Ac @ x, 0.5))
                    x[support] = solve_weighted(Ac[:, support], y, w)
        else:
            x = solve(Ac, y)
            if weighted:
                # Poisson row weights (spec 6.2) from the unweighted fit: w_i = 1 / max(mu_i, 0.5).
                w = 1.0 / np.sqrt(np.maximum(Ac @ x, 0.5))
                x = solve_weighted(Ac, y, w)
        x = x.reshape(-1, S).sum(axis=1)
        for j in np.nonzero(x)[0]:
            out.setdefault(int(j), np.zeros(len(cycles)))[ci] = x[j]
    return c, out


def interpolate_channel(c):
    """Staggered: at each spectrum's time, every window interpolated (makima) to that time, then
    one NNLS. Returns {bin: values at that bin's output events}."""
    Aw, Aw_bins, S, Y, t, win_events, event_window, bin_pos = (_W[k] for k in (
        'Aw', 'Aw_bins', 'S', 'Y', 't', 'win_events', 'event_window', 'bin_pos'))
    series = []
    for ev in win_events:
        yv = Y[ev, c]
        series.append(Akima1DInterpolator(t[ev], yv, method='makima', extrapolate=False) if yv.any() else None)
    out = {}
    for s in range(len(t)):
        w = event_window[s]
        yw = np.zeros(len(win_events))
        for v, f in enumerate(series):
            if f is not None:
                val = f(t[s])
                yw[v] = max(0.0, float(val)) if np.isfinite(val) else 0.0
        yw[w] = Y[s, c]
        if not yw.any():
            continue
        x = solve(Aw, yw)
        if _W.get('weighted', False):
            # Poisson row weights from the unweighted fit, as for ZT Scan (spec 6.2).
            x = solve_weighted(Aw, yw, 1.0 / np.sqrt(np.maximum(Aw @ x, 0.5)))
        x = x.reshape(-1, S).sum(axis=1)
        for j in np.nonzero(Aw_bins[w] > 0.5)[0]:
            if x[j] > 0:
                out.setdefault(int(j), np.zeros(int((bin_pos[j] >= 0).sum())))[bin_pos[j][s]] = x[j]
    return c, out


def hat(t, grid):
    return np.clip(1 - np.abs(t[:, None] - grid[None, :]) / (grid[1] - grid[0]), 0, None)


def time_model_channel(c):
    """One NNLS per block of the time grid for channel c: x_j(t) = sum_g hat_g(t) theta_jg,
    theta >= 0, with sqrt(lam) * second differences of theta along g as extra rows."""
    A, S, Y, t, grid, H, lam, core, pad, out_t, out_block = (_W[k] for k in
        ('A', 'S', 'Y', 't', 'grid', 'H', 'lam', 'core', 'pad', 'out_t', 'out_block'))
    G = len(grid)
    out = {}
    for b, g0 in enumerate(range(0, G, core)):
        e0, e1 = max(0, g0 - pad), min(G, g0 + core + pad)
        rows_t = np.nonzero((t >= grid[e0]) & (t <= grid[e1 - 1]))[0]
        y = Y[rows_t, c]
        if not y.any():
            continue
        Ab = A[rows_t]
        cols = np.nonzero((Ab[y > 0] > 1e-9).any(axis=0))[0]
        rsel = np.nonzero((Ab[:, cols] > 1e-9).any(axis=1))[0]
        ge = e1 - e0
        M = (Ab[np.ix_(rsel, cols)][:, :, None] * H[rows_t[rsel], e0:e1][:, None, :]).reshape(len(rsel), -1)
        D = np.zeros((ge - 2, ge))
        for g in range(ge - 2):
            D[g, g:g + 3] = (1.0, -2.0, 1.0)
        P = np.sqrt(lam) * np.kron(np.eye(len(cols)), D)
        theta = nnls_robust(np.vstack([M, P]), np.concatenate([y[rsel], np.zeros(P.shape[0])]))
        theta = theta.reshape(len(cols), ge)
        # Sum the subbin coefficients into their output bins.
        per_bin = {}
        for jj, col in enumerate(cols):
            j = int(col) // S
            per_bin[j] = per_bin.get(j, 0) + theta[jj]
        for j, th in per_bin.items():
            ks = np.nonzero(out_block[j] == b)[0]
            if len(ks) == 0:
                continue
            vals = hat(out_t[j][ks], grid)[:, e0:e1] @ th
            if vals.any():
                arr = out.setdefault(j, np.zeros(len(out_t[j])))
                arr[ks] = vals
    return c, out


def poisson_deviance(y, mu):
    mu = np.maximum(mu, 1e-9)
    with np.errstate(divide='ignore', invalid='ignore'):
        term = np.where(y > 0, y * np.log(y / mu), 0.0)
    return 2.0 * float(np.sum(term - (y - mu)))


def fit_separable(Ar, Hr, y, R, iterations):
    """y_i ~ sum_r (Ar b_r)_i (Hr s_r)_i with b, s >= 0 and each b_r summing to 1: each source
    has one bin distribution for the whole block and one elution profile. Alternating NNLS, a
    fixed number of iterations. Components start from the positive residual of the fit before."""
    Jc, Ge = Ar.shape[1], Hr.shape[1]
    B = np.zeros((Jc, 0))
    Sg = np.zeros((Ge, 0))
    for r in range(R):
        mu = ((Ar @ B) * (Hr @ Sg)).sum(axis=1) if r else np.zeros(len(y))
        resid = np.maximum(y - mu, 0)
        b = nnls_robust(Ar, resid)
        if b.sum() <= 0:
            break
        b /= b.sum()
        z = (Ar @ b)[:, None] * Hr
        s = nnls_robust(z, resid)
        B = np.column_stack([B, b])
        Sg = np.column_stack([Sg, s])
    R = B.shape[1]
    if R == 0:
        return B, Sg
    for _ in range(iterations):
        Z = np.hstack([(Ar @ B[:, r])[:, None] * Hr for r in range(R)])
        Sg = nnls_robust(Z, y).reshape(R, Ge).T
        W = np.hstack([Ar * (Hr @ Sg[:, r])[:, None] for r in range(R)])
        B = nnls_robust(W, y).reshape(R, Jc).T
        scale = B.sum(axis=0)
        keep = scale > 0
        B, Sg = B[:, keep] / scale[keep], Sg[:, keep] * scale[keep]
        R = B.shape[1]
        if R == 0:
            break
    return B, Sg


def fit_separable_fast(Ar, Hr, y, groups, R, iterations):
    """fit_separable, exploiting that measurements come in groups sharing one row of A (the same
    encoded bin in every sweep, or the same window at every time). The bin-distribution update then
    reduces to R rows per group: with g_i = (h_i . s_r)_r and G_k = sum over the group of g_i g_i^T
    = V L V^T, the group's squared error is ||L^1/2 V^T (B^T a_k) - L^-1/2 V^T sum_i y_i g_i||^2
    plus a constant."""
    Jc, Ge = Ar.shape[1], Hr.shape[1]
    keys, first, inverse = np.unique(groups, return_index=True, return_inverse=True)
    Ak = Ar[first]  # one row of A per group
    ysum = np.bincount(inverse, weights=y, minlength=len(keys))
    B = np.zeros((Jc, 0))
    Sg = np.zeros((Ge, 0))
    for r in range(R):
        mu = ((Ar @ B) * (Hr @ Sg)).sum(axis=1) if r else np.zeros(len(y))
        resid = np.maximum(y - mu, 0)
        b = nnls_robust(Ak, np.bincount(inverse, weights=resid, minlength=len(keys)) if r else ysum)
        if b.sum() <= 0:
            break
        b /= b.sum()
        s = nnls_robust((Ar @ b)[:, None] * Hr, resid)
        B = np.column_stack([B, b])
        Sg = np.column_stack([Sg, s])
    R = B.shape[1]
    for _ in range(iterations if R else 0):
        Z = np.hstack([(Ar @ B[:, r])[:, None] * Hr for r in range(R)])
        Sg = nnls_robust(Z, y).reshape(R, Ge).T
        g = Hr @ Sg
        rows, rhs = [], []
        for k in range(len(keys)):
            idx = inverse == k
            gk = g[idx]
            lam, V = np.linalg.eigh(gk.T @ gk)
            vk = gk.T @ y[idx]
            for m in np.nonzero(lam > 1e-12 * max(lam.max(), 1e-300))[0]:
                rows.append(np.sqrt(lam[m]) * np.kron(V[:, m], Ak[k]))
                rhs.append(V[:, m] @ vk / np.sqrt(lam[m]))
        if not rows:
            break
        B = nnls_robust(np.array(rows), np.array(rhs)).reshape(R, Jc).T
        scale = B.sum(axis=0)
        keep = scale > 0
        B, Sg = B[:, keep] / scale[keep], Sg[:, keep] * scale[keep]
        R = B.shape[1]
        if R == 0:
            break
    return B, Sg


def separable_channel(c):
    """Per time block of channel c: the separable model at rank 1, 2, ... up to max_rank, the
    rank chosen by BIC on the Poisson deviance."""
    A, S, Y, t, grid, H, core, pad, out_t, out_block, max_rank, iterations, row_group, fast = (_W[k] for k in (
        'A', 'S', 'Y', 't', 'grid', 'H', 'core', 'pad', 'out_t', 'out_block', 'max_rank', 'iterations',
        'row_group', 'fast'))
    G = len(grid)
    out = {}
    for b, g0 in enumerate(range(0, G, core)):
        e0, e1 = max(0, g0 - pad), min(G, g0 + core + pad)
        rows_t = np.nonzero((t >= grid[e0]) & (t <= grid[e1 - 1]))[0]
        y = Y[rows_t, c]
        if not y.any():
            continue
        Ab = A[rows_t]
        cols = np.nonzero((Ab[y > 0] > 1e-9).any(axis=0))[0]
        rsel = np.nonzero((Ab[:, cols] > 1e-9).any(axis=1))[0]
        Ar, Hr, yr = Ab[np.ix_(rsel, cols)], H[rows_t[rsel], e0:e1], y[rsel]
        best = None
        for R in range(1, max_rank + 1):
            if fast:
                B, Sg = fit_separable_fast(Ar, Hr, yr, row_group[rows_t[rsel]], R, iterations)
            else:
                B, Sg = fit_separable(Ar, Hr, yr, R, iterations)
            if B.shape[1] < R:
                break
            mu = ((Ar @ B) * (Hr @ Sg)).sum(axis=1)
            per_param = np.log(len(yr)) if _W.get('rank_penalty', 'bic') == 'bic' else 2.0
            bic = poisson_deviance(yr, mu) + R * (len(cols) + Hr.shape[1]) * per_param
            if best is not None and bic >= best[0]:
                break
            best = (bic, B, Sg)
        if best is None:
            continue
        _, B, Sg = best
        # x_j(t) = sum_r b_jr s_r(t), subbins summed into their output bins.
        per_bin = {}
        for jj, col in enumerate(cols):
            j = int(col) // S
            per_bin[j] = per_bin.get(j, 0) + B[jj]
        for j, bj in per_bin.items():
            ks = np.nonzero(out_block[j] == b)[0]
            if len(ks) == 0 or not np.any(bj):
                continue
            vals = (hat(out_t[j][ks], grid)[:, e0:e1] @ Sg) @ bj
            if vals.any():
                arr = out.setdefault(j, np.zeros(len(out_t[j])))
                arr[ks] = vals
    return c, out


def run_variant(fn, state, n_channels, workers):
    with ProcessPoolExecutor(max_workers=workers, initializer=_init, initargs=(state,)) as ex:
        return dict(ex.map(fn, range(n_channels), chunksize=4))


def demux(scheme, Y, variant, args):
    """Returns {channel: {bin: values at the bin's output events}}."""
    if variant.startswith('per-time'):
        if isinstance(scheme, ZtScan):
            # per-time[-poolH][-w]: poolH takes the active positions from the sweeps within H;
            # -w adds Poisson row weights.
            spec = variant.split('-pool')[1].split('-')[0] if '-pool' in variant else '0'
            return run_variant(per_sweep_channel,
                               {'A': scheme.A_solve, 'S': scheme.subbins, 'Y': Y, 'cycles': scheme.cycles,
                                'weighted': variant.endswith('-w'), 'pool': int(spec.rstrip('u')),
                                'union': spec.endswith('u')},
                               Y.shape[1], args.workers)
        bin_pos = []
        for j, evs in enumerate(scheme.bin_output):
            pos = np.full(len(scheme.event_t), -1)
            pos[evs] = np.arange(len(evs))
            bin_pos.append(pos)
        state = {'Aw': scheme.Aw, 'Aw_bins': scheme.Aw_bins, 'S': scheme.subbins, 'Y': Y, 't': scheme.event_t,
                 'weighted': variant.endswith('-w'), 'win_events': scheme.window_events,
                 'event_window': scheme.event_window, 'bin_pos': bin_pos}
        return run_variant(interpolate_channel, state, Y.shape[1], args.workers)
    grid = scheme.grid_default
    if args.grid_step:
        grid = np.arange(grid[0], grid[-1] + 1e-9, args.grid_step)
    dg = grid[1] - grid[0]
    out_t = [scheme.event_t[evs] for evs in scheme.bin_output]
    out_block = [np.clip(np.round((ot - grid[0]) / dg).astype(int), 0, len(grid) - 1) // args.core for ot in out_t]
    state = {'A': scheme.A_solve, 'S': scheme.subbins, 'Y': Y, 't': scheme.event_t, 'grid': grid,
             'H': hat(scheme.event_t, grid), 'lam': args.lam, 'core': args.core, 'pad': args.pad,
             'out_t': out_t, 'out_block': out_block, 'max_rank': args.max_rank, 'iterations': args.iterations,
             'row_group': scheme.event_bin if isinstance(scheme, ZtScan) else scheme.event_window,
             'fast': variant.startswith('separable-fast'), 'rank_penalty': args.rank_penalty}
    fn = separable_channel if variant.startswith('separable') else time_model_channel
    return run_variant(fn, state, Y.shape[1], args.workers)


# ------------------------------------------------------------------------------------- scoring

def trapz(y, t):
    return float(np.trapezoid(y, t)) if len(t) > 1 else 0.0


def score(scheme, targets, tchan, memb, Ys, results, top_score, pepsets, contributors):
    """Per target peptide: quantity (summed top-fragment areas in its own bin) in each sample, for
    the truth, no demux, each variant, and the oracle (the noiseless narrow-window measurement,
    which still carries peptides in the same bin sharing a channel: what a perfect demux gives);
    per-fragment XIC correlation with the truth; and the share of each variant's intensity that
    lands in bins no contributing peptide occupies."""
    rows = []
    for i in range(len(targets)):
        j = scheme.bin_of(targets.mz[i])

        def peak(times):
            """The samples inside the target's peak (own elution at least 1% of its apex), and one
            either side: where a quantity is integrated."""
            inside = np.nonzero(targets.elution(i, times) >= 0.01)[0]
            return np.arange(max(0, inside[0] - 1), min(len(times), inside[-1] + 2))

        evs = scheme.bin_output[j]
        evs = evs[peak(scheme.event_t[evs])]
        T = scheme.event_t[evs]
        nd = scheme.nodemux(targets.mz[i])
        nd = nd[peak(scheme.event_t[nd])]
        chans = sorted(set(int(c) for c in tchan[i]))
        rec = {'seq': targets.seq[i], 'z': int(targets.z[i]), 'mz': float(targets.mz[i]),
               'base': float(targets.base[i]), 'fc': float(targets.fc[i]), 'bin': j,
               'quant': {}, 'xic_r': {}}
        # Positions of the peak's samples in each bin's output arrays (all bins of a ZT Scan
        # sweep share cycle indices; staggered spans are a single bin).
        pos = np.searchsorted(scheme.bin_output[j], evs)
        for sample in (0, 1):
            own = {c: np.zeros(len(T)) for c in chans}
            for f, c in enumerate(tchan[i]):
                own[int(c)] += targets.amount(i, sample) * targets.frag_rel[i][f] * targets.elution(i, T)
            rec['quant'].setdefault('truth', []).append(sum(trapz(own[c], T) for c in chans))
            rec['quant'].setdefault('none', []).append(
                sum(trapz(Ys[sample][nd, c], scheme.event_t[nd]) for c in chans))
            # Quantity from the precursor's own bin, and (ZT Scan) from 3 bins centered on it.
            spans = [('', [j])]
            if isinstance(scheme, ZtScan):
                spans.append((' x3', [jj for jj in (j - 1, j, j + 1) if 0 <= jj < len(scheme.bin_lo)]))
                spans.append((' x5', [jj for jj in range(j - 2, j + 3) if 0 <= jj < len(scheme.bin_lo)]))
            for suffix, js in spans:
                total = 0.0
                rs = []
                for c in chans:
                    est = np.zeros(len(T))
                    for s, k, rel in contributors[c]:
                        peps = pepsets[s]
                        if scheme.bin_of(peps.mz[k]) in js:
                            est = est + peps.amount(k, sample) * rel * peps.elution(k, T)
                    total += trapz(est, T)
                    if sample == 0 and own[c].std() > 0 and est.std() > 0:
                        rs.append(float(np.corrcoef(est, own[c])[0, 1]))
                rec['quant'].setdefault('oracle' + suffix, []).append(total)
                if sample == 0:
                    rec['xic_r']['oracle' + suffix] = float(np.median(rs)) if rs else 0.0
            for v, res in results[sample].items():
                for suffix, js in spans:
                    total = 0.0
                    rs = []
                    for c in chans:
                        est = np.zeros(len(T))
                        for jj in js:
                            part = res.get(c, {}).get(jj)
                            if part is not None:
                                est = est + part[pos]
                        total += trapz(est, T)
                        if sample == 0 and own[c].std() > 0 and est.std() > 0:
                            rs.append(float(np.corrcoef(est, own[c])[0, 1]))
                    rec['quant'].setdefault(v + suffix, []).append(total)
                    if sample == 0:
                        rec['xic_r'][v + suffix] = float(np.median(rs)) if rs else 0.0
            if sample == 0:
                rs = []
                for c in chans:
                    raw = Ys[0][evs, c]
                    if own[c].std() > 0 and raw.std() > 0:
                        rs.append(float(np.corrcoef(raw, own[c])[0, 1]))
                rec['xic_r']['none'] = float(np.median(rs)) if rs else 0.0
        rows.append(rec)

    # Share of each variant's intensity in bins no contributing peptide occupies, and (ZT Scan)
    # more than one bin away from any.
    phantom = {}
    occupied = [set(scheme.bin_of(mz) for mz in m) for m in memb]
    near = [set(jj for j in occ for jj in (j - 1, j, j + 1)) for occ in occupied]
    for v, res in results[0].items():
        tot = off = far = 0.0
        for c, bins in res.items():
            for j, est in bins.items():
                a = trapz(est, scheme.event_t[scheme.bin_output[j]])
                tot += a
                off += a if j not in occupied[c] else 0.0
                far += a if j not in near[c] else 0.0
        phantom[v] = off / tot if tot > 0 else 0.0
        if isinstance(scheme, ZtScan):
            phantom[v + ' x3'] = far / tot if tot > 0 else 0.0
    return rows, phantom


def summarize(rows, phantom):
    variants = [k for k in rows[0]['quant'] if k not in ('truth', 'none') and not k.startswith('oracle')]
    variants += [k for k in rows[0]['quant'] if k.startswith('oracle')]
    base = np.array([r['base'] for r in rows])
    edges = np.quantile(base, [0, 1 / 3, 2 / 3, 1])
    groups = [('all', np.ones(len(rows), bool))]
    names = ('low', 'mid', 'high')
    for g in range(3):
        groups.append(('%s (%.0f-%.0f ions)' % (names[g], edges[g], edges[g + 1]),
                       (base >= edges[g]) & (base <= edges[g + 1])))
    lines = []
    for label, mask in groups:
        lines.append('\n%s: %d peptides' % (label, mask.sum()))
        lines.append('  %-15s %9s %9s %9s %9s %8s' % ('variant', '|log2 A|', 'A in 20%', 'FC err', 'FC slope', 'XIC r'))
        truth = np.array([r['quant']['truth'] for r in rows])[mask]
        fc = np.array([r['fc'] for r in rows])[mask]
        for v in ['none'] + variants:
            q = np.array([r['quant'][v] for r in rows])[mask]
            with np.errstate(divide='ignore', invalid='ignore'):
                la = np.log2(q[:, 0] / truth[:, 0])
                efc = np.log2(q[:, 1] / q[:, 0])
            ok = np.isfinite(la) & np.isfinite(efc)
            slope = np.polyfit(fc[ok], efc[ok], 1)[0] if ok.sum() > 2 else float('nan')
            changed = ok & (fc != 0)
            r = np.array([rr['xic_r'][v] for rr in rows])[mask]
            lines.append('  %-15s %9.3f %8.0f%% %9.3f %9.2f %8.2f%s'
                         % (v, np.median(np.abs(la[ok])), 100 * np.mean(np.abs(la[ok]) < np.log2(1.2)),
                            np.median(np.abs(efc[changed] - fc[changed])) if changed.any() else float('nan'),
                            slope, np.median(r), '' if ok.all() else '  (%d undefined)' % (~ok).sum()))
    lines.append('\n|log2 A|: median |log2(measured / true)| of each target\'s quantity in sample A. FC err: median '
                 '|log2 fold change error| over the targets that change (log2 FC +/-1); FC slope: measured on true '
                 'log2 FC over all targets, 1 = no compression. XIC r: median correlation of fragment XICs with '
                 'the truth. oracle: the noiseless narrow-window measurement (a perfect demux).')
    lines.append('\nintensity in bins no contributing peptide occupies (x3: more than one bin from any): ' +
                 ', '.join('%s %.1f%%' % (v, 100 * p) for v, p in phantom.items()))
    return '\n'.join(lines)


# ---------------------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scheme', choices=('ztscan', 'staggered'), required=True)
    ap.add_argument('--targets', type=int, default=100)
    ap.add_argument('--background', type=int, default=0)
    ap.add_argument('--mz-lo', type=float, default=600.0)
    ap.add_argument('--mz-hi', type=float, default=660.0)
    ap.add_argument('--rt-span', type=float, default=60.0)
    ap.add_argument('--fwhm', type=float, default=None, help='s; default 2.4 (ZT Scan) or 7 (staggered)')
    ap.add_argument('--ions', type=float, nargs=2, default=None,
                    help='log10 range of base-fragment ions per event at apex; default 0 3 (ZT) or 1 4')
    ap.add_argument('--top', type=int, default=20, help='fragments kept per peptide')
    ap.add_argument('--top-score', type=int, default=6, help='fragments scored per target')
    ap.add_argument('--tol-ppm', type=float, default=10.0)
    ap.add_argument('--floor', type=float, default=0.0, help='ions; counts below are censored to 0')
    ap.add_argument('--variants', default='per-time,time-model')
    ap.add_argument('--lam', type=float, default=1.0)
    ap.add_argument('--grid-step', type=float, default=None, help='s; time grid spacing for the block models')
    ap.add_argument('--max-rank', type=int, default=3, help='separable: most sources per channel per block')
    ap.add_argument('--iterations', type=int, default=20, help='separable: alternating NNLS iterations')
    ap.add_argument('--core', type=int, default=8)
    ap.add_argument('--pad', type=int, default=3)
    ap.add_argument('--subbins', type=int, default=1, help='solve columns per output bin')
    ap.add_argument('--kernel-scale', type=float, default=1.0,
                    help='ZT Scan: the simulated transmission is this much wider than the one A assumes')
    ap.add_argument('--rank-penalty', choices=('bic', 'aic'), default='bic',
                    help='separable: per-parameter penalty log(n) (BIC) or 2 (AIC)')
    ap.add_argument('--noiseless', action='store_true', help='expected counts, no Poisson draw')
    ap.add_argument('--snap', action='store_true', help='targets placed at their bin centers')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--workers', type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument('--out', default=None)
    ap.add_argument('--merge', default=None, help='results JSON of an earlier run with the same seed and settings')
    ap.add_argument('--save', default=None, help='pickle the demux output here, for rescoring with --load')
    ap.add_argument('--load', default=None, help='demux output pickled by --save from the same seed and settings')
    args = ap.parse_args()

    zt = args.scheme == 'ztscan'
    fwhm = args.fwhm or (2.4 if zt else 7.0)
    ions = args.ions or ((0.0, 3.0) if zt else (1.0, 4.0))
    rng = np.random.default_rng(args.seed)
    t0 = time.time()
    margin = 20.0
    cands = candidates(FASTA, args.mz_lo - margin, args.mz_hi + margin)
    inner = [c for c in cands if args.mz_lo <= c[2] < args.mz_hi]
    t_lo, t_hi = 0.0, args.rt_span + 10.0
    targets = Peptides(inner, args.targets, 5.0, 5.0 + args.rt_span, fwhm, *ions, args.top, rng, (-1.0, 0.0, 0.0, 1.0))
    background = Peptides(cands, args.background, t_lo - 5, t_hi + 5, fwhm, *ions, args.top, rng, None) \
        if args.background else None
    pepsets = [targets] + ([background] if background is not None else [])
    scheme = ZtScan(args.mz_lo, args.mz_hi, t_lo, t_hi, subbins=args.subbins, sim_scale=args.kernel_scale) if zt \
        else Staggered(args.mz_lo, args.mz_hi, t_lo, t_hi, subbins=args.subbins)
    if args.snap:
        for i in range(len(targets)):
            j = scheme.bin_of(targets.mz[i])
            targets.mz[i] = 0.5 * (scheme.bin_lo[j] + scheme.bin_hi[j])
    centers, tchan = build_channels(targets, args.top_score, args.tol_ppm)
    memb = members(pepsets, centers, args.tol_ppm)
    shared = sum(1 for m in memb if len(m) > 1)
    print('%s: %d candidates, %d targets, %d background; %d events x %d bins; %d channels (%d with >1 contributor); '
          'expected peaks per event mid-run %.0f; setup %.0f s'
          % (args.scheme, len(cands), len(targets), args.background, len(scheme.event_t), len(scheme.bin_lo),
             len(centers), shared, peaks_per_event(scheme, pepsets, 0.5 * (args.mz_lo + args.mz_hi)),
             time.time() - t0))

    Ys = [simulate(scheme, pepsets, memb, s, rng, args.floor, args.noiseless) for s in (0, 1)]
    memb_mz = [[pepsets[s].mz[i] for s, i, _ in m] for m in memb]
    variants = [v for v in args.variants.split(',') if v]
    results = [{}, {}]
    if args.load:
        # Demux output of an earlier run with the same seed and settings.
        with open(args.load, 'rb') as f:
            results = pickle.load(f)
    for v in variants:
        if v in results[0]:
            continue
        t1 = time.time()
        for s in (0, 1):
            results[s][v] = demux(scheme, Ys[s], v, args)
        print('%s: %.0f s' % (v, time.time() - t1))
    if args.save:
        with open(args.save, 'wb') as f:
            pickle.dump(results, f)
    rows, phantom = score(scheme, targets, tchan, memb_mz, Ys, results, args.top_score, pepsets, memb)
    if args.merge:
        # Variants from an earlier run of the same seed and settings (same peptides).
        with open(args.merge) as f:
            other = json.load(f)
        for rec, prev in zip(rows, other['rows']):
            assert rec['seq'] == prev['seq'] and rec['z'] == prev['z']
            for key in ('quant', 'xic_r'):
                for v, val in prev[key].items():
                    rec[key].setdefault(v, val)
        for v, p in other['phantom'].items():
            phantom.setdefault(v, p)
    text = summarize(rows, phantom)
    print(text)
    if args.out:
        with open(args.out, 'w') as f:
            json.dump({'args': vars(args), 'rows': rows, 'phantom': phantom, 'summary': text}, f, indent=1)


if __name__ == '__main__':
    main()
