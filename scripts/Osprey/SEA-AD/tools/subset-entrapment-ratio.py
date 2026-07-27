#!/usr/bin/env python3
"""
Subsample an existing Osprey target+decoy+entrapment library to a lower entrapment
ratio r, REUSING the existing entrapment spectra (no Carafe). Keeps every
target+decoy; keeps p_target/p_decoy for only round(r*n) quartets (rest become
target+decoy only). Deterministic selection mirrors make_natural_entrapment.py
(random.Random(seed) shuffle of pair indices, seed 2024).

Writes a new workdir with:
  - osprey_library_db_pairing.tsv   (subset manifest)
  - carafe_spectral_library.tsv     (library with dropped entrapment spectra removed)

Manifest cols: sequence, decoy, proteins, peptide_type, peptide_pair_index
Library  cols: ModifiedPeptide, StrippedPeptide, ... (join on StrippedPeptide == sequence)
"""
import argparse, os, random, csv, sys
from collections import defaultdict

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True, help='source target+decoy+entrapment dir')
    ap.add_argument('--out', required=True, help='destination dir for the ratio-r library')
    ap.add_argument('--ratio', type=float, required=True)
    ap.add_argument('--seed', type=int, default=2024)
    a = ap.parse_args()

    src_man = os.path.join(a.src, 'osprey_library_db_pairing.tsv')
    src_lib = os.path.join(a.src, 'carafe_spectral_library.tsv')
    os.makedirs(a.out, exist_ok=True)
    out_man = os.path.join(a.out, 'osprey_library_db_pairing.tsv')
    out_lib = os.path.join(a.out, 'carafe_spectral_library.tsv')

    # ---- read manifest, group by pair index (col5, idx4); type is col4 (idx3) ----
    with open(src_man, newline='') as f:
        header = f.readline().rstrip('\n')
        rows = [ln.rstrip('\n').split('\t') for ln in f]
    groups = defaultdict(dict)          # pair_index -> {type: rowidx}
    for i, r in enumerate(rows):
        groups[r[4]][r[3]] = i
    order = sorted(groups, key=lambda k: int(k))
    n = len(order)
    print(f"quartets: {n}", flush=True)

    # ---- deterministic selection of the r fraction that KEEP entrapment ----
    rng = random.Random(a.seed)
    shuf = list(order); rng.shuffle(shuf)
    selected = set(shuf[:round(a.ratio * n)])
    r_actual = len(selected) / n
    print(f"selected {len(selected)}/{n} quartets keep entrapment (r={r_actual:.4f})", flush=True)

    # ---- kept sequences (never remove these) and removed-entrapment sequences ----
    kept_seq = set()
    for k in order:
        g = groups[k]
        kept_seq.add(rows[g['target']][0]); kept_seq.add(rows[g['decoy']][0])
        if k in selected:
            kept_seq.add(rows[g['p_target']][0]); kept_seq.add(rows[g['p_decoy']][0])
    remove_seq = set()
    for k in order:
        if k in selected:
            continue
        g = groups[k]
        for t in ('p_target', 'p_decoy'):
            s = rows[g[t]][0]
            if s not in kept_seq:            # safety: never drop a seq also used by a kept entry
                remove_seq.add(s)
    print(f"entrapment sequences to remove from library: {len(remove_seq)}", flush=True)

    # ---- write subset manifest (target+decoy always; entrapment only if selected) ----
    with open(out_man, 'w', newline='') as f:
        f.write(header + '\n')
        for k in order:
            g = groups[k]
            f.write('\t'.join(rows[g['target']]) + '\n')
            if k in selected:
                f.write('\t'.join(rows[g['p_target']]) + '\n')
            f.write('\t'.join(rows[g['decoy']]) + '\n')
            if k in selected:
                f.write('\t'.join(rows[g['p_decoy']]) + '\n')
    print(f"wrote {out_man}", flush=True)

    # ---- stream the spectral library, drop rows whose StrippedPeptide is removed ----
    kept = dropped = 0
    with open(src_lib, newline='') as fin, open(out_lib, 'w', newline='') as fout:
        libhdr = fin.readline()
        cols = libhdr.rstrip('\n').split('\t')
        sp = cols.index('StrippedPeptide')
        fout.write(libhdr)
        for line in fin:
            i2 = line.find('\t')                         # ModifiedPeptide end
            i3 = line.find('\t', i2 + 1)                 # StrippedPeptide end
            seq = line[i2 + 1:i3]
            if seq in remove_seq:
                dropped += 1
            else:
                fout.write(line); kept += 1
    print(f"library rows kept={kept} dropped={dropped}", flush=True)
    print(f"wrote {out_lib}", flush=True)

if __name__ == '__main__':
    main()
