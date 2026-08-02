#!/usr/bin/env python3
"""Pass-1 entrapment analysis: accepted set taken from experiment-wide q, not from the blib.

Everything in the mean(best-N) analysis is a PASS-1 statistic. The output .blib is the pass-2
reported set, so using it to characterise the accepted entrapment population mixes scopes. This
reads the pass-1 truth directly:

  * `<stem>.1st-pass.fdr_scores.bin` -- 32-byte header + N x 60-byte records, carrying
    `experiment_precursor_qvalue` at offset [28..36]. Written pre-compaction and post first-pass
    protein FDR, one record per input entry.
  * `<stem>.scores.parquet` -- the same rows IN THE SAME ORDER (the sidecar loader matches by
    position, not by joining on entry_id), supplying sequence / protein_ids and the peak
    (apex_rt, start_rt, end_rt, scan_number).

Alignment is asserted per file rather than assumed.

    python pass1_entrap.py <run_dir> <out.json> [parquet_dir]
"""
import json
import os
import sys

import numpy as np
import pyarrow.parquet as pq

REC = np.dtype([('entry_id', '<u4'), ('svm', '<f8'), ('run_prec_q', '<f8'), ('run_pep_q', '<f8'),
                ('exp_prec_q', '<f8'), ('exp_pep_q', '<f8'), ('pep', '<f8'), ('run_prot_q', '<f8')])
assert REC.itemsize == 60
# Harvest cut on experiment_precursor_qvalue. Overridable because it silently bounds what any
# DOWNSTREAM tool can compute: a frontier metric like "discoveries at a matched 1% TRUE FDP"
# scans for the largest acceptance whose measured FDP is still under the cut, and that point
# routinely sits ABOVE q = 0.01. Harvest at 0.01 and the frontier saturates at the q <= 0.01
# discovery count by construction, which reads as a real result rather than a truncation.
# The 163-file arm_*.json files were harvested to q = 0.03 (18.4% of their entries lie above
# 0.01), so anything compared against them must use the same cut.
QCUT = float(os.environ.get('OSPREY_PASS1_QCUT', '0.01'))


def read_sidecar(path):
    with open(path, 'rb') as fh:
        hdr = fh.read(32)
        if hdr[:8] != b'OSPRYFDR':
            raise ValueError(f'bad magic in {path}')
        if hdr[9] != 1:
            raise ValueError(f'{path} is a pass-{hdr[9]} sidecar, expected pass 1')
        n = int.from_bytes(hdr[16:24], 'little')
        return np.fromfile(fh, dtype=REC, count=n)


def main():
    run = sys.argv[1]
    out = sys.argv[2]
    pqdir = sys.argv[3] if len(sys.argv) > 3 else run

    stems = sorted(f[:-len('.1st-pass.fdr_scores.bin')]
                   for f in os.listdir(run) if f.endswith('.1st-pass.fdr_scores.bin'))
    print(f'{len(stems)} pass-1 sidecars in {run}', flush=True)

    info = {}                       # entry_id -> [sequence, protein_ids, min exp_q]
    peaks = {}                      # entry_id -> {file_index: apex_rt}
    for i, stem in enumerate(stems):
        a = read_sidecar(os.path.join(run, stem + '.1st-pass.fdr_scores.bin'))
        t = pq.read_table(os.path.join(pqdir, stem + '.scores.parquet'),
                          columns=['entry_id', 'sequence', 'protein_ids', 'apex_rt'])
        eid = t.column('entry_id').to_numpy()
        if len(eid) != len(a) or not np.array_equal(eid, a['entry_id']):
            raise ValueError(f'{stem}: sidecar/parquet row misalignment')

        sel = np.flatnonzero(a['exp_prec_q'] <= QCUT)
        if len(sel):
            seq = t.column('sequence').take(sel).to_pylist()
            pro = t.column('protein_ids').take(sel).to_pylist()
            rt = t.column('apex_rt').take(sel).to_numpy()
            q = a['exp_prec_q'][sel]
            ids = eid[sel]
            for j, e in enumerate(ids):
                e = int(e)
                rec = info.get(e)
                if rec is None:
                    info[e] = [seq[j], pro[j], float(q[j])]
                elif q[j] < rec[2]:
                    rec[2] = float(q[j])
                peaks.setdefault(e, {})[i] = float(rt[j])
        if (i + 1) % 20 == 0 or i + 1 == len(stems):
            print(f'  {i+1}/{len(stems)}  accepted entry_ids so far {len(info):,}', flush=True)

    ent = {e: v for e, v in info.items() if '_p_target' in (v[1] or '')}
    print(f'\naccepted (pass-1 experiment q <= {QCUT}) entry_ids: {len(info):,}')
    print(f'   of which entrapment: {len(ent):,}')
    json.dump({'files': stems,
               'info': {str(k): v for k, v in info.items()},
               'peaks': {str(k): v for k, v in peaks.items()}},
              open(out, 'w'))
    print(f'wrote {out}')


if __name__ == '__main__':
    main()
