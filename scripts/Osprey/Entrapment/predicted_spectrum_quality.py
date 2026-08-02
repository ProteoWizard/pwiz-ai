#!/usr/bin/env python3
"""Do SHUFFLED entrapment peptides get different predicted spectra from REAL ones?

This is the discriminating experiment behind the 2026-08-02 Astral surprise, where real
Arabidopsis entrapment measured a much HIGHER false-discovery proportion than anagram-shuffle
entrapment - the opposite of the expected direction. Two readings compete:

  1. Arabidopsis is the more honest null and SHUFFLE UNDER-ESTIMATES FDP. peptdeep is trained
     on real peptides; a scrambled sequence is out of distribution, so its predicted spectrum
     may be poor and the entrapment correspondingly hard to match. A null that is unnaturally
     hard to match reports too little false discovery.
  2. Arabidopsis is a BIASED null that over-reports, and shuffle is fine.

Reading 1 predicts a measurable signature IN THE LIBRARY ITSELF, with no search required:
shuffled entrapment should differ from real peptides in predicted-spectrum character, while
real Arabidopsis entrapment should look like real human targets.

Compares, per sampled precursor: fragment count, Shannon entropy of the relative-intensity
vector (how evenly signal is spread), and the largest single fragment's share (how dominated
the spectrum is by one ion). Sampling is by hash of the stripped sequence, one streaming pass
per file, so files are compared without assuming row order.

    python predicted_spectrum_quality.py <lib.tsv>:<label> [...] [--modulus 2000]
"""
import argparse
import math
import sys
import zlib
from collections import defaultdict


def scan(path, modulus):
    """(class -> list of (nfrag, entropy, top_share)) for sampled precursors.

    class is 'target' or 'entrapment', decided from ProteinID exactly as the other tools do.
    """
    cur = defaultdict(list)
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        header = fh.readline().rstrip('\n').split('\t')
        col = {n: i for i, n in enumerate(header)}
        i_mod, i_strip = col['ModifiedPeptide'], col['StrippedPeptide']
        i_z, i_prot, i_int = col['PrecursorCharge'], col['ProteinID'], col['RelativeIntensity']
        acc, key_cls = {}, {}
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) <= max(i_int, i_prot):
                continue
            prot = p[i_prot]
            if prot.startswith('decoy_'):
                continue
            cls = 'entrapment' if '_p_target' in prot else 'target'
            strip = p[i_strip]
            if zlib.crc32(strip.encode()) % modulus:
                continue
            k = (p[i_mod], p[i_z])
            try:
                acc.setdefault(k, []).append(float(p[i_int]))
            except ValueError:
                continue
            key_cls[k] = cls
    out = defaultdict(list)
    for k, ints in acc.items():
        tot = sum(ints)
        if tot <= 0 or len(ints) < 2:
            continue
        ps = [i / tot for i in ints if i > 0]
        ent = -sum(x * math.log(x) for x in ps)
        out[key_cls[k]].append((len(ints), ent, max(ps)))
    return out


def summarise(rows):
    if not rows:
        return None
    n = len(rows)
    def q(vals, f):
        v = sorted(vals)
        return v[min(int(f * len(v)), len(v) - 1)]
    nf = [r[0] for r in rows]; en = [r[1] for r in rows]; tp = [r[2] for r in rows]
    return {
        'n': n,
        'nfrag_mean': sum(nf) / n, 'nfrag_med': q(nf, 0.5),
        'entropy_mean': sum(en) / n, 'entropy_med': q(en, 0.5),
        'top_mean': sum(tp) / n, 'top_med': q(tp, 0.5),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('libs', nargs='+', help='path:label')
    ap.add_argument('--modulus', type=int, default=2000)
    a = ap.parse_args()

    print(f'{"library / class":<34}{"n":>8}{"nfrag":>8}{"nfrag~":>8}'
          f'{"entropy":>9}{"entropy~":>9}{"top%":>8}{"top%~":>8}')
    print('-' * 92)
    for spec in a.libs:
        path, _, label = spec.rpartition(':')
        got = scan(path, a.modulus)
        for cls in ('target', 'entrapment'):
            s = summarise(got.get(cls))
            if not s:
                continue
            print(f'{label + " / " + cls:<34}{s["n"]:>8,}{s["nfrag_mean"]:>8.2f}'
                  f'{s["nfrag_med"]:>8}{s["entropy_mean"]:>9.4f}{s["entropy_med"]:>9.4f}'
                  f'{s["top_mean"]*100:>8.2f}{s["top_med"]*100:>8.2f}')
        sys.stdout.flush()


if __name__ == '__main__':
    main()
