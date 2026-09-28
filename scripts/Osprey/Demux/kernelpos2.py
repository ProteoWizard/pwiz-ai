"""Kernel-position demultiplexing of a ZT Scan slice, fast version, written for DIA-NN.

Per unit and fragment channel (as kernelpos.py), the channel's sources are placed once from the whole
block instead of per sweep:
  1. the channel's Q1 profile summed over the unit's sweeps is fitted on the bin-level columns
     (NNLS, Poisson refit); runs of adjacent solved bins are sources, each at its intensity-weighted
     bin center; sources closer than MERGE Th are merged and those under MIN_SOURCE ions (or
     MIN_SOURCE_FRAC of the channel) dropped;
  2. each source's position is refined by a 1-D search (+/- REFINE Th in REFINE_STEP steps, two passes)
     on the summed profile, with the kernel evaluated at the exact positions;
  3. per sweep, NNLS over just those sources (Poisson refit);
  4. each source's intensity goes to the encoded bin whose center is nearest its position, at the
     m/z of the observed peaks it was solved from in that sweep (each row's peaks counted by the
     share of the row's modeled signal the source explains), as the C# --position-mz does.

Usage: python kernelpos2.py <in.mzML> <out pattern with {layout}> --cycles c0 c1 --mz lo hi
       [--layouts centered:5 centered:7] [--placement <DIA-NN report>]
"""
import argparse
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ztscan_real import NBINS, STEP, channels_of, group_peaks, read_slice, transmission_rows, write_mzml  # noqa: E402
from kernelpos import (MERGE, MIN_SOURCE, MIN_SOURCE_FRAC, REACH, FLOOR, kernel_table, layout_records,  # noqa: E402
                       merge_sources, placement, wnnls)
from scipy.optimize import nnls  # noqa: E402

REFINE = 0.6
REFINE_STEP = 0.1


def sources_of(ar, ccu, ysum, rcu, off, val):
    """Source positions of one channel from its summed profile."""
    xb = wnnls(ar, ysum)
    nz = np.nonzero(xb > 1e-6)[0]
    if len(nz) == 0:
        return np.zeros(0)
    runs = np.split(nz, np.nonzero(np.diff(nz) > 1)[0] + 1)
    pos = np.array([np.average(ccu[r], weights=xb[r]) for r in runs])
    amount = np.array([xb[r].sum() for r in runs])
    pos, amount = merge_sources(pos, amount, MERGE)
    pos = pos[amount >= max(MIN_SOURCE, MIN_SOURCE_FRAC * amount.sum())]
    if len(pos) == 0:
        return pos
    # Weighted residual with weights fixed from the bin-level fit.
    sw = 1.0 / np.sqrt(np.maximum(ar @ xb, FLOOR))
    steps = np.arange(-REFINE, REFINE + REFINE_STEP / 2, REFINE_STEP)
    for _ in range(2):
        for k in range(len(pos)):
            best, best_res = pos[k], np.inf
            for d in steps:
                trial = pos.copy()
                trial[k] = pos[k] + d
                s = np.interp(rcu[:, None] - trial[None, :], off, val, left=0.0, right=0.0)
                a, res = nnls(s * sw[:, None], ysum * sw)
                if res < best_res - 1e-12:
                    best, best_res = trial[k], res
            pos[k] = best
    return pos


def demux_unit(task):
    (A, rc, cc, row_bins, col_bins, core_bins, cycles, core_cycles, peaks, params) = task
    tol, min_ions, min_events, min_out = params
    off, val = kernel_table()
    mz, ions, row, cyc = peaks
    nr, nc = len(row_bins), len(cycles)
    core_cyc = np.isin(cycles, core_cycles)
    core_row = np.isin(row_bins, core_bins)
    stats = {'channels': 0, 'sources': 0, 'in_ions': 0.0, 'passthrough_ions': 0.0}
    if len(mz) == 0:
        return {}, {}, stats
    centers, chan = channels_of(mz, ions, tol, min_ions)
    nch = len(centers)
    stats['channels'] = nch
    in_core = core_row[row] & core_cyc[cyc]
    stats['in_ions'] = float(ions[in_core].sum())
    valid = chan >= 0
    total = np.bincount(chan[valid], weights=ions[valid], minlength=nch)
    cell = np.unique(chan[valid].astype(np.int64) * (nr * nc) + row[valid] * nc + cyc[valid])
    events = np.bincount(cell // (nr * nc), minlength=nch)
    strong = (total >= min_ions) & (events >= min_events)
    through = in_core & (~valid | ~strong[np.maximum(chan, 0)])
    sel = np.nonzero(through)[0]
    stats['passthrough_ions'] = float(ions[sel].sum())
    tb = [row_bins[row[sel]]], [cycles[cyc[sel]]], [mz[sel]], [ions[sel]]
    out = ([], [], [], [])
    order = np.argsort(chan, kind='stable')
    bounds = np.searchsorted(chan[order], np.arange(nch + 1))
    lo_pos, hi_pos = cc[0] - STEP / 2, cc[-1] + STEP / 2
    core_c = np.nonzero(core_cyc)[0]
    for ch in np.nonzero(strong)[0]:
        idx = order[bounds[ch]:bounds[ch + 1]]
        flat = row[idx] * nc + cyc[idx]
        Y = np.bincount(flat, weights=ions[idx], minlength=nr * nc).reshape(nr, nc)
        M = np.bincount(flat, weights=ions[idx] * mz[idx], minlength=nr * nc).reshape(nr, nc)
        cmz = float(np.average(mz[idx], weights=ions[idx]))
        sig = Y.sum(axis=1) > 0
        cols = np.nonzero((A[sig] > 1e-9).any(axis=0))[0]
        rows_used = np.nonzero((A[:, cols] > 1e-9).any(axis=1))[0]
        Ar, Yr, Mr = A[np.ix_(rows_used, cols)], Y[rows_used], M[rows_used]
        rcu = rc[rows_used]
        pos = sources_of(Ar, cc[cols], Yr.sum(axis=1), rcu, off, val)
        if len(pos) == 0:
            continue
        stats['sources'] += len(pos)
        b = col_bins[np.argmin(np.abs(cc[:, None] - pos[None, :]), axis=0)]
        ok = np.isin(b, core_bins) & (pos >= lo_pos) & (pos <= hi_pos)
        if not ok.any():
            continue
        S = np.interp(rcu[:, None] - pos[None, :], off, val, left=0.0, right=0.0)
        for c in core_c:
            y = Yr[:, c]
            if y.sum() <= 0:
                continue
            e = wnnls(S, y)
            w = ok & (e >= min_out)
            if not w.any():
                continue
            model = S * e[None, :]
            mu = model.sum(axis=1)
            share = np.divide(model, mu[:, None], out=np.zeros_like(model), where=mu[:, None] > 0)
            den = share.T @ y
            num = share.T @ Mr[:, c]
            smz = np.where(den > 0, num / np.maximum(den, 1e-300), cmz)
            out[0].append(b[w])
            out[1].append(np.full(w.sum(), cycles[c]))
            out[2].append(smz[w])
            out[3].append(e[w])
    return group_peaks(*tb), group_peaks(*out), stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inp')
    ap.add_argument('out')
    ap.add_argument('--cycles', type=int, nargs=2, required=True)
    ap.add_argument('--mz', type=float, nargs=2, required=True)
    ap.add_argument('--layouts', nargs='+', default=['centered:5', 'centered:7'])
    ap.add_argument('--placement', default='')
    ap.add_argument('--block', type=int, default=12)
    ap.add_argument('--cycle-pad', type=int, default=4)
    ap.add_argument('--group', type=int, default=16)
    ap.add_argument('--context', type=int, default=10)
    ap.add_argument('--tol-ppm', type=float, default=10.0)
    ap.add_argument('--min-ions', type=float, default=8.0)
    ap.add_argument('--min-events', type=int, default=3)
    ap.add_argument('--min-out', type=float, default=0.2)
    ap.add_argument('--workers', type=int, default=6)
    args = ap.parse_args()
    t0 = time.time()
    target0, tstep = 393.439719644102, (629.726233174212 - 393.439719644102) / 200
    targets_all = target0 + tstep * np.arange(NBINS)
    out_bins = [b for b in range(NBINS) if args.mz[0] <= targets_all[b] < args.mz[1]]
    b_lo = max(0, out_bins[0] - args.context - REACH)
    b_hi = min(NBINS - 1, out_bins[-1] + args.context + REACH)
    c0, c1 = args.cycles
    c_lo, c_hi = c0 - args.cycle_pad, c1 + args.cycle_pad
    data = read_slice(args.inp, c_lo, c_hi, b_lo, b_hi, c0, c1, args.workers)
    print('read cycles %d-%d, bins %d-%d: %.0f s' % (c_lo, c_hi, b_lo, b_hi, time.time() - t0), flush=True)
    out_cycles = list(range(c0, c1 + 1))
    read_centers = np.array([data[c_lo][1][b - b_lo][3] for b in range(b_lo, b_hi + 1)])
    tasks = []
    for g0 in range(0, len(out_bins), args.group):
        core_bins = np.array(out_bins[g0:g0 + args.group])
        col_bins = np.arange(max(b_lo, core_bins[0] - args.context), min(b_hi, core_bins[-1] + args.context) + 1)
        row_bins = np.arange(max(b_lo, col_bins[0] - REACH), min(b_hi, col_bins[-1] + REACH) + 1)
        rc, cc = read_centers[row_bins - b_lo], read_centers[col_bins - b_lo]
        A = transmission_rows(rc, cc, 1)
        for k0 in range(0, len(out_cycles), args.block):
            core_cycles = np.array(out_cycles[k0:k0 + args.block])
            cycles = np.arange(max(c_lo, core_cycles[0] - args.cycle_pad), min(c_hi, core_cycles[-1] + args.cycle_pad) + 1)
            mzl, il, rl, cl = [], [], [], []
            for ci, c in enumerate(cycles):
                ms2 = data[c][1]
                for ri, b in enumerate(row_bins):
                    m = ms2[b - b_lo]
                    mzl.append(m[0])
                    il.append(m[1])
                    rl.append(np.full(len(m[0]), ri, np.int32))
                    cl.append(np.full(len(m[0]), ci, np.int32))
            peaks = (np.concatenate(mzl), np.concatenate(il).astype(np.float64), np.concatenate(rl), np.concatenate(cl))
            tasks.append((A, rc, cc, row_bins, col_bins, core_bins, cycles, core_cycles, peaks,
                          (args.tol_ppm, args.min_ions, args.min_events, args.min_out)))
    print('%d units' % len(tasks), flush=True)
    through, kp, totals = {}, {}, {}
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        for k, (t, p, s) in enumerate(ex.map(demux_unit, tasks)):
            through.update(t)
            kp.update(p)
            for key, v in s.items():
                totals[key] = totals.get(key, 0) + v
            if (k + 1) % 10 == 0 or k + 1 == len(tasks):
                print('  units %d/%d, %.0f s' % (k + 1, len(tasks), time.time() - t0), flush=True)
    print('channels %d, sources %d (%.2f per channel); passed through %.1f%% of ions' %
          (totals['channels'], totals['sources'], totals['sources'] / max(totals['channels'], 1),
           100 * totals['passthrough_ions'] / max(totals['in_ions'], 1)), flush=True)
    if args.placement:
        placement(args.placement, data, out_cycles, out_bins, b_lo, {'kernelpos2': kp})
    for layout in args.layouts:
        kind, k = layout.split(':')[:2]
        path = args.out.replace('{layout}', kind + k)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_mzml(path, data, out_cycles, layout_records(kind, int(k), 0, data, out_cycles, out_bins, b_lo, through, kp))
        print('wrote %s: %.0f s' % (path, time.time() - t0), flush=True)


if __name__ == '__main__':
    main()
