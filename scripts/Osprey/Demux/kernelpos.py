"""Kernel-position demultiplexing of a ZT Scan slice: each fragment channel's sources are placed once,
from their whole elution, at continuous positions, instead of per sweep on fixed 1.18 Th positions.

Per unit (a group of encoded bins by a block of sweeps, with context, as in ztscan_real.py) and per
fragment channel (the same histogram channels):
  blind     the current solve: per sweep, NNLS over every 1.18 Th position in reach (bin-averaged
            kernel), Poisson-weighted refit.
  kernelpos 1. the channel's Q1 profile summed over the unit's sweeps is fitted with the kernel at
               every position of a GRID Th grid (NNLS, Poisson-weighted refit); the solution's
               clusters (gaps over GAP Th) are the channel's sources, each at its intensity-weighted
               position;
            2. per sweep, NNLS over just those sources' columns (the kernel at each position),
               Poisson-weighted refit;
            3. each source's intensity goes to the encoded bin whose target is nearest its position.
Both write demultiplexed peaks by (bin, sweep) at the channel's m/z; weak channels pass through.

Placement check (library-free output, scored with DIA-NN's identifications on A1): for each identified
precursor in the slice, its top library fragments' demultiplexed intensity near its apex, by the bin it
landed in relative to the precursor's own bin.

Usage: python kernelpos.py <in.mzML> <out pattern with {method} and {layout}> --cycles c0 c1 --mz lo hi
       [--layouts tiled:1 tiled:2 centered:3 framed:3:1] [--report <DIA-NN report.parquet>] [--write]
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ztscan_real import (ID, KERNEL, NBINS, STEP, channels_of, group_peaks, merge_close,  # noqa: E402
                         read_slice, transmission_rows, write_mzml)

LIB = r'D:\test\osprey-runs\ztscan\library\ztscan_carafe_lib.parquet'
GRID = 0.1
GAP = 0.3
FLOOR = 0.5
TOP = 6
MATCH_PPM = 20.0
APEX = 2
REACH = 9


def wnnls(m, y):
    x = nnls(m, y, maxiter=50 * m.shape[1])[0]
    sw = 1.0 / np.sqrt(np.maximum(m @ x, FLOOR))
    return nnls(m * sw[:, None], y * sw, maxiter=50 * m.shape[1])[0]


def kernel_table():
    rows = np.genfromtxt(KERNEL, delimiter='\t', skip_header=1)
    off, val = rows[:, 0], np.nan_to_num(rows[:, 1])
    half = np.linspace(-STEP / 2, STEP / 2, 41)
    return off, val / np.interp(half, off, val).mean()


MERGE = 0.8          # Th: sources of one channel closer than this are one source
MIN_SOURCE = 2.0     # ions over the unit: smaller sources are dropped
MIN_SOURCE_FRAC = 0.05
SEED_IONS = 20.0     # a source this strong can seed a precursor group
GROUP_CORR = 0.7     # elution correlation to join a group


def position_sigma(ions):
    """A fragment's Q1 position error (Th) by its ions, from position_test.py: about 0.5 Th at 300 ions."""
    return np.clip(0.5 * np.sqrt(300.0 / np.maximum(ions, 1e-9)), 0.3, 1.5)


def merge_sources(pos, amount, gap):
    """Sources closer than gap merged, left to right, at their amount-weighted position."""
    o = np.argsort(pos, kind='stable')
    pos, amount = pos[o], amount[o]
    new = np.concatenate([[True], np.diff(pos) > gap])
    g = np.cumsum(new) - 1
    a = np.bincount(g, weights=amount)
    return np.bincount(g, weights=amount * pos) / np.maximum(a, 1e-300), a


def group_sources(pos, ions, E):
    """Precursor groups: strongest source first, each ungrouped source whose elution correlates at
    GROUP_CORR or better and whose position agrees within twice the combined position error joins.
    Returns each source's placement position (its group's weighted position, else its own) and group."""
    n = len(pos)
    sig = position_sigma(ions)
    en = E - E.mean(axis=1, keepdims=True)
    norm = np.linalg.norm(en, axis=1)
    order = np.argsort(pos, kind='stable')
    sp = pos[order]
    group = np.full(n, -1)
    place = pos.copy()
    for s in np.argsort(-ions, kind='stable'):
        if group[s] >= 0 or ions[s] < SEED_IONS or norm[s] == 0:
            continue
        lo, hi = np.searchsorted(sp, [pos[s] - 3.0, pos[s] + 3.0])
        cand = order[lo:hi]
        cand = cand[group[cand] < 0]
        cand = cand[np.abs(pos[cand] - pos[s]) <= 2 * np.sqrt(sig[cand] ** 2 + sig[s] ** 2)]
        corr = en[cand] @ en[s] / (norm[cand] * norm[s] + 1e-12)
        members = cand[corr >= GROUP_CORR]
        if s not in members:
            members = np.append(members, s)
        group[members] = s
        w = ions[members] / sig[members] ** 2
        place[members] = (pos[members] * w).sum() / w.sum()
    return place, group


def demux_unit(task):
    (A, rc, cc, row_bins, col_bins, core_bins, cycles, core_cycles, peaks, params) = task
    tol, min_ions, min_events, min_out, do_blind = params
    off, val = kernel_table()
    mz, ions, row, cyc = peaks
    nr, nc = len(row_bins), len(cycles)
    core_cyc = np.isin(cycles, core_cycles)
    core_row = np.isin(row_bins, core_bins)
    stats = {'channels': 0, 'sources': 0, 'in_ions': 0.0, 'passthrough_ions': 0.0, 'grouped': 0, 'groups': 0}
    if len(mz) == 0:
        return {}, {}, {}, {}, stats
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
    blind = ([], [], [], [])
    order = np.argsort(chan, kind='stable')
    bounds = np.searchsorted(chan[order], np.arange(nch + 1))
    core_col = np.isin(col_bins, core_bins)
    lo_pos, hi_pos = cc[0] - STEP / 2, cc[-1] + STEP / 2
    src_pos, src_e, src_mz = [], [], []   # every kernelpos source: position, elution over the unit, m/z
    for ch in np.nonzero(strong)[0]:
        idx = order[bounds[ch]:bounds[ch + 1]]
        Y = np.bincount(row[idx] * nc + cyc[idx], weights=ions[idx], minlength=nr * nc).reshape(nr, nc)
        cmz = float(np.average(mz[idx], weights=ions[idx]))
        sig = Y.sum(axis=1) > 0
        cols = np.nonzero((A[sig] > 1e-9).any(axis=0))[0]
        rows_used = np.nonzero((A[:, cols] > 1e-9).any(axis=1))[0]
        Ar, Yr = A[np.ix_(rows_used, cols)], Y[rows_used]
        active = np.nonzero(Yr.any(axis=0))[0]

        # blind: per sweep over every position in reach.
        for c in (active if do_blind else []):
            if not core_cyc[c]:
                continue
            x = wnnls(Ar, Yr[:, c])
            keep = core_col[cols] & (x >= min_out)
            blind[0].append(col_bins[cols[keep]])
            blind[1].append(np.full(keep.sum(), cycles[c]))
            blind[2].append(np.full(keep.sum(), cmz))
            blind[3].append(x[keep])

        # kernelpos: positions from the summed profile, then per sweep over those sources.
        rcu = rc[rows_used]
        g_lo = max(lo_pos - 10.0, rcu[sig[rows_used]].min() - 10.5)
        g_hi = min(hi_pos + 10.0, rcu[sig[rows_used]].max() + 10.5)
        grid = np.arange(g_lo, g_hi + GRID / 2, GRID)
        K = np.interp(rcu[:, None] - grid[None, :], off, val, left=0.0, right=0.0)
        xg = wnnls(K, Yr.sum(axis=1))
        nz = np.nonzero(xg > 1e-6)[0]
        if len(nz) == 0:
            continue
        breaks = np.nonzero(np.diff(grid[nz]) > GAP + 1e-9)[0] + 1
        clusters = np.split(nz, breaks)
        pos = np.array([np.average(grid[cl], weights=xg[cl]) for cl in clusters])
        amount = np.array([xg[cl].sum() for cl in clusters])
        pos, amount = merge_sources(pos, amount, MERGE)
        keep = amount >= max(MIN_SOURCE, MIN_SOURCE_FRAC * amount.sum())
        pos = pos[keep]
        if len(pos) == 0:
            continue
        S = np.interp(rcu[:, None] - pos[None, :], off, val, left=0.0, right=0.0)
        stats['sources'] += len(pos)
        E = np.zeros((len(pos), nc))
        for c in active:
            E[:, c] = wnnls(S, Yr[:, c])
        src_pos.append(pos)
        src_e.append(E)
        src_mz.append(np.full(len(pos), cmz))

    # Each source placed at its own position (kernelpos) or its precursor group's (grouped); the
    # encoded bin whose center is nearest the placement; only core bins and core sweeps written.
    kp, grouped = ([], [], [], []), ([], [], [], [])
    if src_pos:
        pos = np.concatenate(src_pos)
        E = np.concatenate(src_e)
        smz = np.concatenate(src_mz)
        place, group = group_sources(pos, E.sum(axis=1), E)
        stats['grouped'] = int((group >= 0).sum())
        stats['groups'] = int(len(np.unique(group[group >= 0])))
        core_c = np.nonzero(core_cyc)[0]
        for out, p in ((kp, pos), (grouped, place)):
            b = col_bins[np.argmin(np.abs(cc[:, None] - p[None, :]), axis=0)]
            ok = np.isin(b, core_bins) & (p >= lo_pos) & (p <= hi_pos)
            for c in core_c:
                w = ok & (E[:, c] >= min_out)
                out[0].append(b[w])
                out[1].append(np.full(w.sum(), cycles[c]))
                out[2].append(smz[w])
                out[3].append(E[w, c])
    return group_peaks(*tb), group_peaks(*blind), group_peaks(*kp), group_peaks(*grouped), stats


def layout_records(kind, k, m, data, out_cycles, out_bins, b_lo, through, demuxed):
    """centered:k, tiled:k, or framed:k:m (tiles of k bins carrying m bins more on each side)."""
    empty = (np.zeros(0), np.zeros(0))
    out = {}
    for c in out_cycles:
        ms2 = data[c][1]
        recs = []
        groups = [out_bins[i:i + k] for i in range(0, len(out_bins), k)] if kind != 'centered' else [[b] for b in out_bins]
        for g in groups:
            if kind == 'centered':
                dem_bins = range(g[0] - k // 2, g[0] + k // 2 + 1)
            elif kind == 'framed':
                dem_bins = range(g[0] - m, g[-1] + m + 1)
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


def placement(report, data, out_cycles, out_bins, b_lo, methods):
    """For DIA-NN's identified precursors in the slice: their top fragments' demultiplexed intensity
    near the apex, by the bin it landed in relative to the precursor's own bin (the bin whose target
    is nearest the precursor m/z)."""
    rep = pd.read_parquet(report, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Q.Value'])
    rep = rep[rep['Q.Value'] <= 0.01].drop_duplicates('Precursor.Id')
    targets = np.array([data[out_cycles[0]][1][b - b_lo][3] for b in out_bins])
    rts = np.array([data[c][1][0][2] for c in out_cycles])
    lo_mz, hi_mz = targets[3] - STEP / 2, targets[-4] + STEP / 2
    rep = rep[rep['Precursor.Mz'].between(lo_mz, hi_mz) & rep['RT'].between(rts[APEX], rts[-APEX - 1])]
    frag = pq.read_table(LIB, columns=['Precursor.Id', 'Product.Mz', 'Relative.Intensity'],
                         filters=[('Precursor.Id', 'in', list(rep['Precursor.Id']))]).to_pandas()
    frag = frag.sort_values(['Precursor.Id', 'Relative.Intensity'], ascending=[True, False], kind='stable')
    frag = frag.groupby('Precursor.Id', sort=True).head(TOP)
    fr = {pid: g['Product.Mz'].values for pid, g in frag.groupby('Precursor.Id', sort=True)}
    offsets = np.arange(-3, 4)
    table = {name: np.zeros(len(offsets)) for name in methods}
    per_prec = {name: [] for name in methods}
    for _, r in rep.iterrows():
        pb = out_bins[int(np.argmin(np.abs(targets - r['Precursor.Mz'])))]
        ci = int(np.argmin(np.abs(rts - r['RT'])))
        cs = out_cycles[max(0, ci - APEX):ci + APEX + 1]
        for name, dem in methods.items():
            v = np.zeros(len(offsets))
            for fm in fr.get(r['Precursor.Id'], []):
                tol = fm * MATCH_PPM * 1e-6
                for j, d in enumerate(offsets):
                    for c in cs:
                        p = dem.get((pb + d, c))
                        if p is not None:
                            a, b = np.searchsorted(p[0], [fm - tol, fm + tol])
                            v[j] += p[1][a:b].sum()
            table[name] += v
            if v.sum() > 0:
                per_prec[name].append(v[3] / v.sum())
    print('\nplacement of %d identified precursors\' top-%d fragment signal near the apex, by bin offset '
          'from the precursor\'s own bin' % (len(rep), TOP))
    print('%-10s %s   own   +/-1   median own share' % ('method', ' '.join('%6d' % d for d in offsets)))
    for name, v in table.items():
        s = v / v.sum()
        print('%-10s %s  %.2f  %.2f   %.2f' % (name, ' '.join('%6.3f' % x for x in s), s[3], s[2:5].sum(),
                                            np.median(per_prec[name]) if per_prec[name] else float('nan')))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inp')
    ap.add_argument('out')
    ap.add_argument('--cycles', type=int, nargs=2, required=True)
    ap.add_argument('--mz', type=float, nargs=2, required=True)
    ap.add_argument('--layouts', nargs='+', default=['tiled:1', 'tiled:2', 'centered:3', 'framed:3:1'])
    ap.add_argument('--report', default=r'D:\test\osprey-runs\ztscan\diann\C_plain\report.parquet')
    ap.add_argument('--write', action='store_true', help='write the kernelpos mzML layouts')
    ap.add_argument('--block', type=int, default=12)
    ap.add_argument('--cycle-pad', type=int, default=4)
    ap.add_argument('--group', type=int, default=16)
    ap.add_argument('--context', type=int, default=10)
    ap.add_argument('--tol-ppm', type=float, default=10.0)
    ap.add_argument('--min-ions', type=float, default=8.0)
    ap.add_argument('--min-events', type=int, default=3)
    ap.add_argument('--min-out', type=float, default=0.2)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--blind', action='store_true', help='also run the per-sweep blind solve, for the placement check')
    args = ap.parse_args()
    t0 = time.time()
    # Output bins by their reported targets (FIRST in ztscan_real is bin 0's lower edge).
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
                          (args.tol_ppm, args.min_ions, args.min_events, args.min_out, args.blind)))
    print('%d units' % len(tasks), flush=True)
    through, blind, kp, grouped, totals = {}, {}, {}, {}, {}
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        for k, (t, b, p, g, s) in enumerate(ex.map(demux_unit, tasks)):
            through.update(t)
            blind.update(b)
            kp.update(p)
            grouped.update(g)
            for key, v in s.items():
                totals[key] = totals.get(key, 0) + v
            if (k + 1) % 10 == 0 or k + 1 == len(tasks):
                print('  units %d/%d, %.0f s' % (k + 1, len(tasks), time.time() - t0), flush=True)
    print('channels %d, sources %d (%.2f per channel); %d grouped into %d groups (%.1f per group); '
          'passed through %.1f%% of ions' %
          (totals['channels'], totals['sources'], totals['sources'] / max(totals['channels'], 1), totals['grouped'],
           totals['groups'], totals['grouped'] / max(totals['groups'], 1),
           100 * totals['passthrough_ions'] / max(totals['in_ions'], 1)), flush=True)
    methods = {'kernelpos': kp, 'grouped': grouped}
    if args.blind:
        methods = {'blind': blind, **methods}
    placement(args.report, data, out_cycles, out_bins, b_lo, methods)
    if args.write:
        for layout in args.layouts:
            parts = layout.split(':')
            kind, k, m = parts[0], int(parts[1]), int(parts[2]) if len(parts) > 2 else 0
            name = kind + parts[1] + ('m' + parts[2] if len(parts) > 2 else '')
            for method, dem in (('kernelpos', kp), ('grouped', grouped)):
                path = args.out.replace('{method}', method).replace('{layout}', name)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                write_mzml(path, data, out_cycles, layout_records(kind, k, m, data, out_cycles, out_bins, b_lo, through, dem))
                print('wrote %s: %.0f s' % (path, time.time() - t0), flush=True)


if __name__ == '__main__':
    main()
