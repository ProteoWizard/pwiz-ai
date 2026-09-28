"""Per-channel separable demultiplexing of a slice of a real ZT Scan run, written as mzML for DIA-NN.

Reads cycles [c0, c1] and encoded bins [b0, b1] (plus context) from a vendor-centroided msconvert
mzML, drops the zero-intensity flanks SCIEX centroiding adds, and writes one mzML of the slice:
its MS1 spectra, and its MS2 spectra of bins [b0, b1] with the same ids, times and windows.
  --mode raw     MS2 peaks as acquired (the baseline, through the same writer)
  --mode demux   each product-ion channel demultiplexed on its own

Demux, per unit of a time block (cycles) by a group of encoded bins, with context on both axes:
  channels  fragment m/z channels from maxima of the unit's intensity-weighted m/z histogram
            (1 ppm bins, smoothed over +/-4 ppm), each peak assigned to the nearest channel within
            the tolerance; peaks near no channel pass through unchanged;
  model     a channel's counts over the unit's events (rows: encoded bins; columns: cycles) as
            sum over sources r of (A b_r) s_r^T, with A the measured transmission (rows: events'
            bins; columns: source bins), b_r >= 0 summing to 1 (the source's bin distribution,
            fixed over the block) and s_r >= 0 its elution over cycles. Rank 1, and 2 or 3 when
            the Poisson deviance says so (BIC). Alternating NNLS, a fixed number of iterations.
  output    x_j(c) = sum_r b_jr s_r(c) at the channel's m/z, for the unit's core bins and cycles.

Intensities are divided by 100 on input (one ion is about 100 counts on this instrument) and
multiplied back on output.

Usage: python ztscan_real.py <in.mzML> <out.mzML> --cycles c0 c1 --mz lo hi [--mode demux|raw]
"""
import argparse
import os
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from psims.mzml.writer import MzMLWriter
from pyteomics import mzml
from scipy.optimize import lsq_linear, nnls

KERNEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kernels', 'A1_rt3-8.profile.tsv')
ID = 'sample=1 period=1 cycle=%d experiment=%d'
ION = 100.0
STEP = 1.181866
FIRST = 392.760634
NBINS = 429


# ------------------------------------------------------------------------------------ reading

def read_cycles(args):
    """MS2 peaks (zeros dropped) of bins [lo, hi] for a list of cycles, and the metadata of each."""
    path, cycles, lo, hi, want_ms1 = args
    reader = mzml.PreIndexedMzML(path)
    out = []
    for c in cycles:
        ms1 = None
        if want_ms1:
            s = reader.get_by_id(ID % (c, 1))
            it = s['intensity array']
            nz = it > 0
            ms1 = (s['m/z array'][nz], it[nz].astype(np.float32), float(s['scanList']['scan'][0]['scan start time']))
        ms2 = []
        for b in range(lo, hi + 1):
            s = reader.get_by_id(ID % (c, b + 2))
            it = s['intensity array']
            nz = it > 0
            p = s['precursorList']['precursor'][0]
            iw = p['isolationWindow']
            ms2.append((s['m/z array'][nz], (it[nz] / ION).astype(np.float32),
                        float(s['scanList']['scan'][0]['scan start time']),
                        float(iw['isolation window target m/z']), float(iw['isolation window lower offset']),
                        float(iw['isolation window upper offset']), float(p['activation'].get('collision energy', 0.0))))
        out.append((c, ms1, ms2))
    return out


def read_slice(path, c_lo, c_hi, b_lo, b_hi, out_c0, out_c1, workers):
    cycles = list(range(c_lo, c_hi + 1))
    chunks = [cycles[k::workers] for k in range(workers)]
    data = {}
    with ProcessPoolExecutor(max_workers=workers) as ex:
        for part in ex.map(read_cycles, [(path, ch, b_lo, b_hi, True) for ch in chunks]):
            for c, ms1, ms2 in part:
                data[c] = (ms1 if out_c0 <= c <= out_c1 else None, ms2)
    return data


# ------------------------------------------------------------------------------------ the model

def nnls_robust(M, b):
    try:
        return nnls(M, b, maxiter=50 * M.shape[1])[0]
    except RuntimeError:
        return lsq_linear(M, b, bounds=(0, np.inf), method='bvls').x


def poisson_deviance(y, mu):
    mu = np.maximum(mu, 1e-9)
    with np.errstate(divide='ignore', invalid='ignore'):
        term = np.where(y > 0, y * np.log(y / mu), 0.0)
    return 2.0 * float(np.sum(term - (y - mu)))


def fit_rank(A, Y, R, iterations, init=None):
    """Y (rows x cycles) ~ A B S^T, B >= 0 with unit column sums, S >= 0."""
    nr, nc = Y.shape
    nj = A.shape[1]
    if init is None:
        b = nnls_robust(A, Y.sum(axis=1))
        if b.sum() <= 0:
            return None
        B = (b / b.sum())[:, None]
    else:
        B = init
    for _ in range(iterations):
        P = A @ B
        if B.shape[1] == 1:
            p = P[:, 0]
            pp = p @ p
            if pp <= 0:
                return None
            S = np.maximum(Y.T @ p / pp, 0.0)[:, None]
        else:
            S = np.array([nnls_robust(P, Y[:, c]) for c in range(nc)])
        G = S.T @ S
        lam, V = np.linalg.eigh(G)
        keep = lam > 1e-12 * max(lam.max(), 1e-300)
        if not keep.any():
            return None
        W = V[:, keep] * np.sqrt(lam[keep])  # R x k
        rhs = (Y @ S @ (V[:, keep] / np.sqrt(lam[keep]))).T.ravel()  # vec of (nr x k), column-major
        design = np.kron(W.T, A)  # (k nr) x (R nj)
        B = nnls_robust(design, rhs).reshape(B.shape[1], nj).T
        tot = B.sum(axis=0)
        ok = tot > 0
        if not ok.any():
            return None
        B = B[:, ok] / tot[ok]
    P = A @ B
    if B.shape[1] == 1:
        p = P[:, 0]
        S = np.maximum(Y.T @ p / max(p @ p, 1e-300), 0.0)[:, None]
    else:
        S = np.array([nnls_robust(P, Y[:, c]) for c in range(nc)])
    return B, S


def solve_channel(A, Y, max_rank, iterations):
    """Rank chosen by BIC on the Poisson deviance; returns B (cols x R), S (cycles x R)."""
    n = Y.size
    best = None
    fit = None
    for R in range(1, max_rank + 1):
        if R == 1:
            fit = fit_rank(A, Y, 1, iterations)
        else:
            B, S = fit
            resid = np.maximum(Y - (A @ B) @ S.T, 0)
            b = nnls_robust(A, resid.sum(axis=1))
            if b.sum() <= 0:
                break
            fit = fit_rank(A, Y, R, iterations, init=np.column_stack([B, b / b.sum()]))
        if fit is None:
            break
        B, S = fit
        mu = (A @ B) @ S.T
        dev = poisson_deviance(Y, mu)
        bic = dev + B.shape[1] * (A.shape[1] + Y.shape[1]) * np.log(n)
        if best is not None and bic >= best[0]:
            break
        best = (bic, B, S, dev)
        # A fit already consistent with counting noise needs no further source.
        if dev < 1.5 * np.count_nonzero(Y) + 10:
            break
    return None if best is None else (best[1], best[2])


def channels_of(mz, ions, tol_ppm, min_ions):
    """Channel centers (maxima of the smoothed 1 ppm intensity histogram, non-maximum suppressed
    within the tolerance) and each peak's channel (-1 for none within the tolerance)."""
    key = np.floor(np.log(mz) * 1e6).astype(np.int64)
    ukeys, inv = np.unique(key, return_inverse=True)
    w = np.bincount(inv, weights=ions)
    cs = np.concatenate([[0.0], np.cumsum(w)])
    lo = np.searchsorted(ukeys, ukeys - 4, side='left')
    hi = np.searchsorted(ukeys, ukeys + 4, side='right')
    smooth = cs[hi] - cs[lo]
    order = np.argsort(-smooth, kind='stable')
    order = order[smooth[order] >= min_ions]
    taken = np.zeros(len(ukeys), bool)
    centers = []
    rad = int(np.ceil(tol_ppm))
    for k in order:
        if taken[k]:
            continue
        centers.append(ukeys[k])
        a = np.searchsorted(ukeys, ukeys[k] - rad, side='left')
        b = np.searchsorted(ukeys, ukeys[k] + rad, side='right')
        taken[a:b] = True
    centers = np.sort(np.array(centers, dtype=np.int64))
    if len(centers) == 0:
        return centers, np.full(len(mz), -1)
    pos = np.clip(np.searchsorted(centers, key), 1, len(centers) - 1) if len(centers) > 1 else np.zeros(len(key), int)
    if len(centers) > 1:
        left = centers[pos - 1]
        right = centers[pos]
        pos = np.where(np.abs(key - left) <= np.abs(key - right), pos - 1, pos)
    chan = np.where(np.abs(key - centers[pos]) <= tol_ppm, pos, -1)
    return centers, chan


def demux_unit(task):
    """One unit: returns {(bin, cycle): (mz array, intensity array)} for its core events."""
    (A_full, S_sub, row_bins, col_bins, core_bins, cycles, core_cycles, peaks, params) = task
    tol, min_ions, min_events, max_rank, iterations, min_out, solver = params
    mz, ions, row, cyc = peaks
    nr, nc = len(row_bins), len(cycles)
    out = {}
    core_row = np.isin(row_bins, core_bins)
    core_cyc = np.isin(cycles, core_cycles)
    if len(mz) == 0:
        return out, out, {}
    centers, chan = channels_of(mz, ions, tol, min_ions)
    stats = {'channels': len(centers), 'demuxed': 0, 'rank2+': 0, 'passthrough_ions': 0.0, 'in_ions': 0.0}
    eb, ec, em, ev = [], [], [], []  # emitted peaks: bin, cycle, m/z, ions
    db, dc, dm, dv = [], [], [], []  # demultiplexed peaks, kept apart so the output can spread them

    in_core = core_row[row] & core_cyc[cyc]
    stats['in_ions'] = float(ions[in_core].sum())
    # A channel too weak to fit (too few ions or events) passes through, as do peaks near no channel.
    nch = len(centers)
    valid = chan >= 0
    total = np.bincount(chan[valid], weights=ions[valid], minlength=nch)
    cell = np.unique(chan[valid].astype(np.int64) * (nr * nc) + row[valid] * nc + cyc[valid])
    events = np.bincount(cell // (nr * nc), minlength=nch)
    strong = (total >= min_ions) & (events >= min_events)
    through = in_core & (~valid | ~strong[np.maximum(chan, 0)])
    sel = np.nonzero(through)[0]
    eb.append(row_bins[row[sel]])
    ec.append(cycles[cyc[sel]])
    em.append(mz[sel])
    ev.append(ions[sel])
    stats['passthrough_ions'] += float(ions[sel].sum())
    order = np.argsort(chan, kind='stable')
    bounds = np.searchsorted(chan[order], np.arange(nch + 1))
    for ch in np.nonzero(strong)[0]:
        idx = order[bounds[ch]:bounds[ch + 1]]
        Y = np.bincount(row[idx] * nc + cyc[idx], weights=ions[idx], minlength=nr * nc).reshape(nr, nc)
        cmz = float(np.average(mz[idx], weights=ions[idx]))
        sig = Y.sum(axis=1) > 0
        cols = np.nonzero((A_full[sig] > 1e-9).any(axis=0))[0]
        rows_used = np.nonzero((A_full[:, cols] > 1e-9).any(axis=1))[0]
        Ar, Yr = A_full[np.ix_(rows_used, cols)], Y[rows_used]
        if solver in ('persweep', 'persweep-w'):
            # One NNLS per cycle: X (source columns x cycles). persweep-w refits with Poisson row
            # weights from the first fit, w_i = 1 / max(mu_i, 0.5) (spec 6.2).
            X = np.zeros((len(cols), nc))
            for c in np.nonzero(Yr.any(axis=0))[0]:
                x = nnls_robust(Ar, Yr[:, c])
                if solver == 'persweep-w':
                    sw = 1.0 / np.sqrt(np.maximum(Ar @ x, 0.5))
                    x = nnls_robust(Ar * sw[:, None], Yr[:, c] * sw)
                X[:, c] = x
        else:
            fit = solve_channel(Ar, Yr, max_rank, iterations)
            if fit is None:
                continue
            B, S = fit
            stats['rank2+'] += int(B.shape[1] > 1)
            X = B @ S.T  # x_j(c) = sum_r b_jr s_r(c)
        stats['demuxed'] += 1
        # Sum subbin columns into their bins.
        src_bin = col_bins[cols // S_sub]
        for jb in np.unique(src_bin):
            if jb not in core_bins:
                continue
            x = X[src_bin == jb].sum(axis=0)
            cs = np.nonzero(core_cyc & (x >= min_out))[0]
            db.append(np.full(len(cs), jb))
            dc.append(cycles[cs])
            dm.append(np.full(len(cs), cmz))
            dv.append(x[cs])
    return group_peaks(eb, ec, em, ev), group_peaks(db, dc, dm, dv), stats


def group_peaks(eb, ec, em, ev):
    """{(bin, cycle): (m/z, ions)} from lists of parallel arrays, m/z sorted."""
    out = {}
    if not eb:
        return out
    eb, ec, em, ev = (np.concatenate(a) for a in (eb, ec, em, ev))
    o = np.lexsort((em, ec, eb))
    eb, ec, em, ev = eb[o], ec[o], em[o], ev[o]
    cut = np.nonzero((np.diff(eb) != 0) | (np.diff(ec) != 0))[0] + 1
    for s, e in zip(np.concatenate([[0], cut]), np.concatenate([cut, [len(eb)]])):
        if e > s:
            out[(int(eb[s]), int(ec[s]))] = (em[s:e], ev[s:e])
    return out


def merge_close(mz, ions, ppm):
    """Peaks within ppm of their neighbor summed into one at the intensity-weighted m/z."""
    if len(mz) < 2:
        return mz, ions
    o = np.argsort(mz, kind='stable')
    mz, ions = mz[o], ions[o]
    new = np.concatenate([[True], np.diff(mz) > mz[1:] * ppm * 1e-6])
    grp = np.cumsum(new) - 1
    w = np.bincount(grp, weights=ions)
    m = np.bincount(grp, weights=ions * mz) / np.maximum(w, 1e-300)
    return m, w


# ------------------------------------------------------------------------------------ writing

def write_mzml(path, data, out_cycles, records):
    """Each cycle's MS1 from data, then its MS2 records (see layout_records)."""
    count = sum(1 for c in out_cycles if data[c][0] is not None) + sum(len(records[c]) for c in out_cycles)
    with MzMLWriter(open(path, 'wb'), close=True) as out:
        out.controlled_vocabularies()
        out.file_description(['MS1 spectrum', 'MSn spectrum', 'centroid spectrum'])
        out.software_list([out.Software(id='ztscan_real', version='0.1', params=['custom unreleased software tool'])])
        out.instrument_configuration_list([out.InstrumentConfiguration(id='IC1', component_list=[])])
        out.data_processing_list([out.DataProcessing(
            [out.ProcessingMethod(order=1, software_reference='ztscan_real', params=['Conversion to mzML'])], id='DP1')])
        with out.run(id='run1', instrument_configuration='IC1'):
            with out.spectrum_list(count=count):
                for c in out_cycles:
                    ms1, ms2 = data[c]
                    if ms1 is not None:
                        out.write_spectrum(ms1[0], ms1[1], id=ID % (c, 1), centroided=True, scan_start_time=ms1[2],
                                           params=[{'ms level': 1}, 'MS1 spectrum'])
                    for sid, rt, target, lo_off, hi_off, ce, mzs, ions in records[c]:
                        out.write_spectrum(
                            np.asarray(mzs, dtype=np.float64), np.asarray(ions, dtype=np.float64) * ION,
                            id=sid, centroided=True, scan_start_time=rt,
                            params=[{'ms level': 2}, 'MSn spectrum'],
                            precursor_information={
                                'mz': target, 'activation': ['beam-type collision-induced dissociation',
                                                             {'collision energy': ce}],
                                'isolation_window': [lo_off, target, hi_off]})


# ------------------------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inp')
    ap.add_argument('out')
    ap.add_argument('--cycles', type=int, nargs=2, required=True, help='first and last output cycle')
    ap.add_argument('--mz', type=float, nargs=2, required=True, help='output precursor m/z range')
    ap.add_argument('--mode', choices=('demux', 'raw'), default='demux')
    ap.add_argument('--solver', choices=('separable', 'persweep', 'persweep-w'), default='separable')
    ap.add_argument('--layouts', nargs='+', default=['centered:1'],
                    help='centered:k or tiled:k (see layout_records); one file each, the out path\'s {layout} '
                         'replaced by e.g. tiled5')
    ap.add_argument('--block', type=int, default=12, help='core cycles per unit')
    ap.add_argument('--cycle-pad', type=int, default=4)
    ap.add_argument('--group', type=int, default=16, help='core bins per unit')
    ap.add_argument('--context', type=int, default=10, help='source bins beyond the core on each side')
    ap.add_argument('--subbins', type=int, default=1)
    ap.add_argument('--tol-ppm', type=float, default=10.0)
    ap.add_argument('--min-ions', type=float, default=8.0, help='channel total below which peaks pass through')
    ap.add_argument('--min-events', type=int, default=3)
    ap.add_argument('--max-rank', type=int, default=3)
    ap.add_argument('--iterations', type=int, default=12)
    ap.add_argument('--min-out', type=float, default=0.2, help='ions; smaller demuxed values are not written')
    ap.add_argument('--workers', type=int, default=4)
    args = ap.parse_args()

    t0 = time.time()
    centers_all = FIRST + STEP * (np.arange(NBINS) + 0.5)
    out_bins = [b for b in range(NBINS) if args.mz[0] <= centers_all[b] < args.mz[1]]
    reach = 9  # bins a source's transmission reaches
    b_lo = max(0, out_bins[0] - args.context - reach)
    b_hi = min(NBINS - 1, out_bins[-1] + args.context + reach)
    c0, c1 = args.cycles
    c_lo, c_hi = c0 - args.cycle_pad, c1 + args.cycle_pad
    data = read_slice(args.inp, c_lo, c_hi, b_lo, b_hi, c0, c1, args.workers)
    print('read cycles %d-%d, bins %d-%d (%d output bins): %.0f s' % (c_lo, c_hi, b_lo, b_hi, len(out_bins),
                                                                    time.time() - t0), flush=True)
    out_cycles = list(range(c0, c1 + 1))
    spectra = {'_b_lo': b_lo}
    if args.mode == 'raw':
        for c in out_cycles:
            for b in out_bins:
                m = data[c][1][b - b_lo]
                spectra[(b, c)] = (m[0], m[1])
    else:
        read_centers = np.array([data[c_lo][1][b - b_lo][3] for b in range(b_lo, b_hi + 1)])
        tasks = []
        for g0 in range(0, len(out_bins), args.group):
            core_bins = np.array(out_bins[g0:g0 + args.group])
            col_bins = np.arange(max(b_lo, core_bins[0] - args.context), min(b_hi, core_bins[-1] + args.context) + 1)
            row_bins = np.arange(max(b_lo, col_bins[0] - reach), min(b_hi, col_bins[-1] + reach) + 1)
            # Rows: events of row_bins; columns: source (sub)bins of col_bins.
            rc = read_centers[row_bins - b_lo]
            cc = read_centers[col_bins - b_lo]
            A = transmission_rows(rc, cc, args.subbins)
            for k0 in range(0, len(out_cycles), args.block):
                core_cycles = np.array(out_cycles[k0:k0 + args.block])
                cycles = np.arange(max(c_lo, core_cycles[0] - args.cycle_pad),
                                   min(c_hi, core_cycles[-1] + args.cycle_pad) + 1)
                mzl, il, rl, cl = [], [], [], []
                for ci, c in enumerate(cycles):
                    ms2 = data[c][1]
                    for ri, b in enumerate(row_bins):
                        m = ms2[b - b_lo]
                        mzl.append(m[0])
                        il.append(m[1])
                        rl.append(np.full(len(m[0]), ri, np.int32))
                        cl.append(np.full(len(m[0]), ci, np.int32))
                peaks = (np.concatenate(mzl), np.concatenate(il).astype(np.float64), np.concatenate(rl),
                         np.concatenate(cl))
                params = (args.tol_ppm, args.min_ions, args.min_events, args.max_rank, args.iterations, args.min_out,
                          args.solver)
                tasks.append((A, args.subbins, row_bins, col_bins, core_bins, cycles, core_cycles, peaks, params))
        print('%d units' % len(tasks), flush=True)
        totals = {}
        done = 0
        through, demuxed = {}, {}
        with ProcessPoolExecutor(max_workers=args.workers) as ex:
            for passed, dem, stats in ex.map(demux_unit, tasks):
                through.update(passed)
                demuxed.update(dem)
                for k, v in stats.items():
                    totals[k] = totals.get(k, 0) + v
                done += 1
                if done % 10 == 0 or done == len(tasks):
                    print('  units %d/%d, %.0f s' % (done, len(tasks), time.time() - t0), flush=True)
        print('channels %d, demuxed %d (rank 2+: %d); ions in %.0f, passed through %.0f (%.1f%%)'
              % (totals.get('channels', 0), totals.get('demuxed', 0), totals.get('rank2+', 0),
                 totals.get('in_ions', 0), totals.get('passthrough_ions', 0),
                 100 * totals.get('passthrough_ions', 0) / max(totals.get('in_ions', 1), 1)), flush=True)
        # Each bin's spectrum: its own pass-through peaks, and the demultiplexed peaks of the bins
        # within the spread of it (0: its own bin only), peaks of one channel merged. One output
        # file per spread; the out path's {s} is replaced by the spread.
        for layout in args.layouts:
            kind, k = layout.split(':')
            records = layout_records(kind, int(k), data, out_cycles, out_bins, b_lo, through, demuxed)
            path = args.out.replace('{layout}', kind + k)
            write_mzml(path, data, out_cycles, records)
            print('wrote %s: %.0f s' % (path, time.time() - t0), flush=True)
        return
    records = layout_records('raw', 1, data, out_cycles, out_bins, b_lo, spectra, {})
    write_mzml(args.out, data, out_cycles, records)
    print('wrote %s: %.0f s' % (args.out, time.time() - t0), flush=True)


def layout_records(kind, k, data, out_cycles, out_bins, b_lo, through, demuxed):
    """The MS2 spectra to write per cycle: (id, time, target, lower offset, upper offset, CE, m/z, ions).

    raw         each bin's own peaks (through holds them).
    centered:k  one spectrum per encoded bin under its own 1.18 Th label, carrying its pass-through
                peaks and the demultiplexed peaks of the k bins centered on it (k odd).
    tiled:k     one spectrum per k consecutive bins, labeled with their combined window, carrying
                their pass-through and demultiplexed peaks.
    Demultiplexed peaks of one channel from several bins are merged.
    """
    empty = (np.zeros(0), np.zeros(0))
    out = {}
    for c in out_cycles:
        ms2 = data[c][1]
        recs = []
        if kind == 'tiled':
            groups = [out_bins[i:i + k] for i in range(0, len(out_bins), k)]
        else:
            groups = [[b] for b in out_bins]
        for g in groups:
            if kind == 'centered':
                dem_bins = range(g[0] - k // 2, g[0] + k // 2 + 1)
            else:
                dem_bins = g
            dem = [demuxed.get((b, c), empty) for b in dem_bins]
            dm_mz, dm_v = merge_close(np.concatenate([p[0] for p in dem]), np.concatenate([p[1] for p in dem]), 5.0)
            tp = [through.get((b, c), empty) for b in g]
            mzs = np.concatenate([p[0] for p in tp] + [dm_mz])
            ions = np.concatenate([p[1] for p in tp] + [dm_v])
            o = np.argsort(mzs, kind='stable')
            first, last, mid = ms2[g[0] - b_lo], ms2[g[-1] - b_lo], ms2[g[len(g) // 2] - b_lo]
            lo, hi = first[3] - first[4], last[3] + last[5]
            target = 0.5 * (lo + hi)
            recs.append((ID % (c, g[0] + 2), mid[2], target, target - lo, hi - target, mid[6], mzs[o], ions[o]))
        out[c] = recs
    return out


def transmission_rows(row_centers, col_centers, subbins):
    """A[i, j]: transmission of source (sub)bin j of col_centers into the event at row_centers[i],
    averaged over the source (sub)bin; scaled so a precursor at the center of its own bin is
    transmitted at 1 on average."""
    rows = np.genfromtxt(KERNEL, delimiter='\t', skip_header=1)
    off, val = rows[:, 0], np.nan_to_num(rows[:, 1])
    half = np.linspace(-STEP / 2, STEP / 2, 41)
    val = val / np.interp(half, off, val).mean()
    width = STEP / subbins
    src = (col_centers[:, None] - STEP / 2 + width * (np.arange(subbins) + 0.5)).ravel()
    pts = (np.arange(21) + 0.5) / 21 * width - width / 2
    d = row_centers[:, None, None] - (src[None, :, None] + pts[None, None, :])
    return np.interp(d, off, val, left=0.0, right=0.0).mean(axis=2)


if __name__ == '__main__':
    main()
