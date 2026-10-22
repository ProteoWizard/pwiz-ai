"""Compares two centroided mzML files spectrum by spectrum: the C# Centrix port against Rust Centrix.

Usage: python centrix_parity.py <rust.mzML> <csharp.mzML>

Spectra are matched by id. Within a spectrum, centroids are matched in m/z order when the counts agree;
otherwise the spectrum is reported as a count mismatch and its centroids matched to the nearest within 0.01 Th.
"""
import sys
import numpy as np
from pyteomics import mzml


def read(path):
    spectra = {}
    with mzml.MzML(path) as reader:
        for s in reader:
            spectra[s['id']] = (np.asarray(s['m/z array'], dtype=float), np.asarray(s['intensity array'], dtype=float))
    return spectra


def main():
    rust = read(sys.argv[1])
    cs = read(sys.argv[2])
    ids = [i for i in rust if i in cs]
    print('spectra: rust %d, c# %d, common %d' % (len(rust), len(cs), len(ids)))
    n_rust = n_cs = n_same_count = 0
    mz_err = []
    rel_err = []
    mismatched = []
    unmatched_rust = unmatched_cs = 0
    for i in ids:
        rm, ri = rust[i]
        cm, ci = cs[i]
        n_rust += len(rm)
        n_cs += len(cm)
        if len(rm) == len(cm):
            n_same_count += 1
            if len(rm):
                mz_err.extend(np.abs(rm - cm))
                rel_err.extend(np.abs(ri - ci) / np.maximum(np.abs(ri), 1e-30))
            continue
        mismatched.append((i, len(rm), len(cm)))
        if len(cm) == 0:
            unmatched_rust += len(rm)
            continue
        idx = np.clip(np.searchsorted(cm, rm), 1, len(cm) - 1) if len(cm) > 1 else np.zeros(len(rm), dtype=int)
        for k, m in enumerate(rm):
            j = idx[k]
            best = j if len(cm) == 1 or abs(cm[j] - m) < abs(cm[j - 1] - m) else j - 1
            if abs(cm[best] - m) <= 0.01:
                mz_err.append(abs(cm[best] - m))
                rel_err.append(abs(ri[k] - ci[best]) / max(abs(ri[k]), 1e-30))
            else:
                unmatched_rust += 1
        unmatched_cs += max(len(cm) - len(rm), 0)
    mz_err = np.array(mz_err)
    rel_err = np.array(rel_err)
    print('centroids: rust %d, c# %d' % (n_rust, n_cs))
    print('spectra with equal counts: %d of %d' % (n_same_count, len(ids)))
    print('count mismatches: %d spectra; rust centroids unmatched %d; c# surplus %d' % (len(mismatched), unmatched_rust, unmatched_cs))
    for m in mismatched[:10]:
        print('  %s: rust %d, c# %d' % m)
    if len(mz_err):
        for q in (50, 99, 99.9, 100):
            print('m/z |diff| p%g: %.3g Th; intensity rel diff p%g: %.3g' % (q, np.percentile(mz_err, q), q, np.percentile(rel_err, q)))
        print('fraction of matched centroids within 1e-4 Th and 1e-4 relative: %.6f' % np.mean((mz_err <= 1e-4) & (rel_err <= 1e-4)))


if __name__ == '__main__':
    main()
