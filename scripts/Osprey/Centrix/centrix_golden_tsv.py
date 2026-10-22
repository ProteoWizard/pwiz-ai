"""Writes Rust Centrix's centroids of the fixture slices as the golden TSV CentrixTest pins the C# port against.

Usage: python centrix_golden_tsv.py <out.tsv> <input.mzML>=<rust-output.mzML> [...]

One row per centroid: the input file's name, the spectrum's MS level, its ordinal among the spectra of that level in
the file (as Osprey's reader lists them), and the centroid's m/z and intensity at the precision Rust wrote them.
"""
import os
import sys
import numpy as np
from pyteomics import mzml


def main():
    out = sys.argv[1]
    rows = []
    for pair in sys.argv[2:]:
        source, rust = pair.split('=')
        ordinal = {1: 0, 2: 0}
        with mzml.MzML(rust) as reader:
            for s in reader:
                level = s['ms level']
                mz = s['m/z array']
                intensity = s['intensity array']
                for m, v in zip(mz, intensity):
                    rows.append('%s\t%d\t%d\t%s\t%s' % (os.path.basename(source), level, ordinal[level],
                                                        repr(float(m)), repr(intensity.dtype.type(v).item())))
                ordinal[level] += 1
        print('%s: %s, m/z %s, intensity %s' % (rust, ordinal, mz.dtype, intensity.dtype))
    with open(out, 'w', newline='\r\n') as f:
        f.write('File\tMsLevel\tOrdinal\tMz\tIntensity\n')
        for row in rows:
            f.write(row + '\n')
    print('%s: %d centroids' % (out, len(rows)))


if __name__ == '__main__':
    main()
