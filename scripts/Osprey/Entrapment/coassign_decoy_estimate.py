#!/usr/bin/env python3
"""First believable estimate of peak co-assignment INCLUDING decoys (issue #4522).

Deliberately independent of the Osprey C# panel, which currently mis-counts decoys: this reads the
run's own artifacts and does the accounting from scratch, so it can be checked against the panel
rather than inheriting its bug.

Decoys have no meaningful q - they are the basis on which q is computed - so they are included by
SCORE: a decoy counts as detected when its composite score clears the acceptance boundary, i.e. the
lowest score among the accepted target/entrapment set at that scope.

  run scope        boundary and decoy score are the precursor's best WITHIN a file
  experiment scope boundary and decoy score are max() ACROSS files

max() across runs is the DEFAULT experiment aggregation. These runs use it, so computing the
aggregate here with max() is correct for them - and deliberately kept, because recomputing it is
what makes this an independent check. Under OSPREY_EXPERIMENT_AGG mean-best-N it would be wrong,
which is why sidecar v4 persists the score each q was computed from
(`experiment_aggregate_score`, issue #4522).

Since v4 the sidecar carries that value, so this script also CROSS-CHECKS it: the persisted
aggregate must equal the max computed here. That is an end-to-end test of the C# producer against
an implementation that shares no code with it. A mismatch is reported and is a real defect - do not
"fix" it by adopting the persisted value here, which would collapse the two into one implementation
and leave nothing checking either.

    python coassign_decoy_estimate.py <run_dir> [--use-persisted]

--use-persisted feeds the panel's own `experiment_aggregate_score` into this script's accounting
instead of the max computed here. Identical output either way says the persisted field is a
correct and sufficient input to the rule, which localizes any remaining disagreement with the C#
panel to how the C# CONSUMES it rather than to the field or the rule.
"""
import bisect
import glob
import os
import re
import sys

import numpy as np
import pyarrow.parquet as pq

REC = np.dtype([('entry_id', '<u4'), ('svm', '<f8'), ('run_prec_q', '<f8'), ('run_pep_q', '<f8'),
                ('exp_prec_q', '<f8'), ('exp_pep_q', '<f8'), ('pep', '<f8'), ('run_prot_q', '<f8'),
                ('exp_agg', '<f8')])
SIDECAR_VERSION = 4
DECOY_BIT = np.uint32(0x80000000)
QCUT, RT_TOL, MZ_TOL = 0.01, 0.05, 0.01
PROTON = 1.007276
AA = {'A': 71.037114, 'R': 156.101111, 'N': 114.042927, 'D': 115.026943, 'C': 103.009185,
      'E': 129.042593, 'Q': 128.058578, 'G': 57.021464, 'H': 137.058912, 'I': 113.084064,
      'L': 113.084064, 'K': 128.094963, 'M': 131.040485, 'F': 147.068414, 'P': 97.052764,
      'S': 87.032028, 'T': 101.047679, 'W': 186.079313, 'Y': 163.063329, 'V': 99.068414}
H2O = 18.010565
MOD = re.compile(r'\[([^\]]*)\]')
# The library writes mods either as a signed mass or as a UniMod accession; both appear in one run.
UNIMOD = {4: 57.021464, 35: 15.994915, 1: 42.010565, 21: 79.966331, 7: 0.984016, 6: 58.005479}


DECOY_PREFIX = 'DECOY_'


def mz_of(modseq, charge):
    """Precursor m/z from the modified sequence. Bracketed numeric mods are added; UniMod tokens
    fall back to a mass-less residue, which only shifts a modified precursor and is flagged.

    The DECOY_ prefix MUST be stripped first. Without that, the residue walk below reads D, E, C
    and Y as amino acids and adds ~510 Da to every decoy's precursor mass, so no decoy ever lands
    in the +/-0.01 m/z window of a target and the decoy co-assignment rate collapses to near zero.
    That artifact is what produced the earlier "decoys co-assign BELOW targets (0.27-0.45x)"
    reading; it was measuring a broken mass, not a property of decoys.
    """
    if modseq.startswith(DECOY_PREFIX):
        modseq = modseq[len(DECOY_PREFIX):]
    total, ok = H2O, True
    for tok in MOD.findall(modseq):
        t = tok.replace('+', '').strip()
        m = re.match(r'(?i)unimod:(\d+)$', t)
        if m:
            acc = int(m.group(1))
            if acc in UNIMOD:
                total += UNIMOD[acc]
            else:
                ok = False
            continue
        try:
            total += float(t)
        except ValueError:
            ok = False
    for ch in MOD.sub('', modseq):
        if ch in AA:
            total += AA[ch]
        elif ch.isalpha():
            ok = False
    return (total + charge * PROTON) / charge, ok


args = [a for a in sys.argv[1:] if not a.startswith('--')]
use_persisted = '--use-persisted' in sys.argv[1:]
run = args[0]
stems = sorted(f[:-len('.1st-pass.fdr_scores.bin')]
               for f in os.listdir(run) if f.endswith('.1st-pass.fdr_scores.bin'))
print('experiment aggregate source: '
      + ('PERSISTED experiment_aggregate_score' if use_persisted else 'max() computed here'))
print(f'{len(stems)} file(s) in {run}\n')

# ---- per file: best-scoring row per precursor (entry id) ----
files = []           # per file: dict entry_id -> (score, apex_rt, mz, cls)
exp_best = {}        # entry_id -> max score across files  (the experiment aggregate)
run_acc = []         # per file: set of accepted non-decoy entry ids (run q)
exp_acc = set()      # entry ids accepted non-decoy at experiment q
cls_of = {}          # entry_id -> 'target' | 'entrapment' | 'decoy'
unparsed = 0

persisted_agg = {}   # entry_id -> experiment_aggregate_score as written by Osprey

for stem in stems:
    with open(os.path.join(run, stem + '.1st-pass.fdr_scores.bin'), 'rb') as fh:
        hdr = fh.read(32)
        if hdr[:8] != b'OSPRYFDR':
            sys.exit(f'{stem}: not an FDR sidecar (bad magic)')
        if hdr[8] != SIDECAR_VERSION:
            sys.exit(f'{stem}: sidecar version {hdr[8]}, this script reads v{SIDECAR_VERSION}')
        a = np.fromfile(fh, dtype=REC, count=int.from_bytes(hdr[16:24], 'little'))
    t = pq.read_table(os.path.join(run, stem + '.scores.parquet'),
                      columns=['entry_id', 'charge', 'modified_sequence', 'protein_ids', 'apex_rt'])
    eid = t.column('entry_id').to_numpy()
    if len(eid) != len(a) or not np.array_equal(eid, a['entry_id']):
        sys.exit(f'{stem}: sidecar/parquet row misalignment')
    ch = t.column('charge').to_numpy()
    ms = t.column('modified_sequence').to_pylist()
    pro = t.column('protein_ids').to_pylist()
    rt = t.column('apex_rt').to_numpy()

    best, acc = {}, set()
    for i in range(len(eid)):
        e = int(eid[i])
        s = float(a['svm'][i])
        prev = best.get(e)
        if prev is None or s > prev[0]:
            mz, ok = mz_of(ms[i], int(ch[i]) or 2)
            if not ok:
                unparsed += 1
            if e not in cls_of:
                p = pro[i] or ''
                cls_of[e] = ('decoy' if (np.uint32(e) & DECOY_BIT) else
                             ('entrapment' if '_p_target' in p else 'target'))
            best[e] = (s, float(rt[i]), mz)
        if cls_of.get(e) != 'decoy':
            if a['run_prec_q'][i] <= QCUT:
                acc.add(e)
            if a['exp_prec_q'][i] <= QCUT:
                exp_acc.add(e)
        if e not in exp_best or s > exp_best[e]:
            exp_best[e] = s
        persisted_agg[e] = float(a['exp_agg'][i])
    files.append(best)
    run_acc.append(acc)

# Cross-check the persisted aggregate against the one computed above. Same quantity, two
# implementations sharing no code; under the default aggregation they must agree exactly.
mismatch = [(e, exp_best[e], persisted_agg[e]) for e in exp_best
            if persisted_agg.get(e) != exp_best[e]]
if use_persisted:
    exp_best = persisted_agg
if mismatch:
    print(f'!! {len(mismatch)} entry(s) where the persisted experiment_aggregate_score disagrees '
          f'with max() computed here - the C# producer is wrong, or these runs are not using the '
          f'default aggregation:')
    for e, want, got in mismatch[:10]:
        print(f'     entry {e}: computed {want:.6f}, persisted {got:.6f}')
else:
    print(f'persisted experiment_aggregate_score matches computed max() for all '
          f'{len(exp_best):,} precursors')

# ---- acceptance boundaries: lowest accepted target/entrapment score at each scope ----
run_cut = [min((f[e][0] for e in acc if e in f), default=None) for f, acc in zip(files, run_acc)]
exp_cut = min((exp_best[e] for e in exp_acc), default=None)
print('acceptance boundary (lowest accepted target/entrapment composite score)')
for stem, c in zip(stems, run_cut):
    print(f'  run  {stem[:44]:<46} {c:.4f}')
print(f'  experiment (max across runs){"":18} {exp_cut:.4f}')
if unparsed:
    print(f'  [{unparsed} rows had an unparseable modification; their m/z is approximate]')


def measure(scope):
    """Included set + co-assignment for one scope. Returns per-class (n, shared, better)."""
    inc = []            # per file: list of (mz, rt, score, entry_id)
    member = {}         # entry_id -> class, for precursors included anywhere
    for fi, best in enumerate(files):
        rows = []
        for e, (s, rt, mz) in best.items():
            c = cls_of[e]
            if c == 'decoy':
                keep = (s >= run_cut[fi]) if scope == 'run' else (exp_best[e] >= exp_cut)
            else:
                keep = (e in run_acc[fi]) if scope == 'run' else (e in exp_acc)
            if keep:
                rows.append((mz, rt, s, e))
                member[e] = c
        inc.append(rows)

    shared, better = set(), set()
    for rows in inc:
        targets = sorted((mz, rt, s, e) for mz, rt, s, e in rows if cls_of[e] == 'target')
        mzs = [r[0] for r in targets]
        for mz, rt, s, e in rows:
            lo = bisect.bisect_left(mzs, mz - MZ_TOL)
            hi = bisect.bisect_right(mzs, mz + MZ_TOL)
            for j in range(lo, hi):
                mz2, rt2, s2, e2 = targets[j]
                if e2 == e or abs(rt2 - rt) > RT_TOL:
                    continue
                shared.add(e)
                if s2 > s:
                    better.add(e)
    out = {}
    for c in ('target', 'entrapment', 'decoy'):
        ids = [e for e, cc in member.items() if cc == c]
        out[c] = (len(ids), sum(1 for e in ids if e in shared), sum(1 for e in ids if e in better))
    return out


for scope in ('run', 'experiment'):
    r = measure(scope)
    nt = r['target'][0]
    print(f'\n=== {scope}-level, q <= {QCUT:g} ===')
    print(f"{'class':<12}{'detected':>10}{'shares a peak':>15}{'outscored':>11}{'rate':>9}{'vs target':>11}")
    base = r['target'][2] / nt if nt else float('nan')
    for c in ('target', 'entrapment', 'decoy'):
        n, sh, be = r[c]
        if not n:
            continue
        rate = be / n
        print(f'{c:<12}{n:>10,}{sh:>15,}{be:>11,}{rate*100:>8.2f}%'
              f'{(rate/base if base else float("nan")):>10.2f}x')
    nd = r['decoy'][0]
    print(f'  decoys / (targets+entrapment) = {nd}/{nt + r["entrapment"][0]} = '
          f'{100.0*nd/max(nt + r["entrapment"][0],1):.2f}%   (expect ~1% by construction)')
