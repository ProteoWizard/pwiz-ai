#!/usr/bin/env python3
"""Strip decoy rows from a Carafe spectral library TSV, keeping the header plus targets
and entrapment (target + p_target).

In THIS dataset's libraries decoys are marked ONLY by a decoy_/rev_ PREFIX on the
ProteinID column -- the `Decoy` column is 0 on every row. Filtering on that column is a
silent no-op that produces a library still full of decoys, and the run that follows looks
fine while measuring nothing. Never "fix" the column; match the prefix.

The output is the gendecoy arm's library: Osprey generates its own decoys from it while
the entrapment peptides stay in place as the independent oracle.

Streams line by line, so it is safe on the 13 GB libraries.

Usage: python strip-decoys.py <in.tsv> <out.tsv> [--protein-column ProteinID]
"""
import argparse
import re
import sys

DECOY_PREFIX = re.compile(r'^(decoy_|rev_)', re.IGNORECASE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('out')
    ap.add_argument('--protein-column', default='ProteinID',
                    help='header name of the protein accession column (default: ProteinID)')
    a = ap.parse_args()

    kept = dropped = 0
    with open(a.src, encoding='utf-8', newline='') as fin, \
         open(a.out, 'w', encoding='utf-8', newline='') as fout:
        header = fin.readline()
        cols = header.rstrip('\r\n').split('\t')
        if a.protein_column not in cols:
            sys.exit(f"no '{a.protein_column}' column in {a.src}; found: {', '.join(cols[:12])}...")
        pi = cols.index(a.protein_column)
        fout.write(header)
        for line in fin:
            parts = line.rstrip('\r\n').split('\t')
            if len(parts) > pi and DECOY_PREFIX.match(parts[pi]):
                dropped += 1
            else:
                fout.write(line)
                kept += 1

    print(f"kept={kept} dropped={dropped} -> {a.out}", flush=True)
    if dropped == 0:
        sys.exit(f"ERROR: no decoy rows matched a decoy_/rev_ prefix in '{a.protein_column}'. "
                 f"The output is NOT a gendecoy library. Check the column name.")


if __name__ == '__main__':
    main()
