"""Writes a non-indexed mzML holding chosen spectra of a source mzML, byte for byte.

Usage: python slice_mzml.py <source.mzML> <out.mzML> <index>[,<index>...]

Each chosen <spectrum> element is copied unchanged except its index attribute, which is renumbered from 0. The
header up to <spectrumList> is the source's; chromatograms and the source's offset index are dropped.
"""
import re
import sys


def main():
    source, out, indices = sys.argv[1], sys.argv[2], [int(v) for v in sys.argv[3].split(',')]
    text = open(source, 'rb').read().decode('utf-8')
    head_start = text.index('<mzML')
    list_match = re.search(r'<spectrumList\b[^>]*>', text)
    starts = [m.start() for m in re.finditer(r'<spectrum\s', text)]
    blocks = []
    for i in indices:
        start = starts[i]
        end = text.index('</spectrum>', start) + len('</spectrum>')
        block = text[start:end]
        block = re.sub(r'\bindex="\d+"', 'index="%d"' % len(blocks), block, count=1)
        blocks.append(block)
    spectrum_list = re.sub(r'\bcount="\d+"', 'count="%d"' % len(blocks), list_match.group(0), count=1)
    with open(out, 'wb') as f:
        f.write(b'<?xml version="1.0" encoding="utf-8"?>\n')
        f.write(text[head_start:list_match.start()].encode('utf-8'))
        f.write(spectrum_list.encode('utf-8'))
        f.write(b'\n')
        for block in blocks:
            f.write(block.encode('utf-8'))
            f.write(b'\n')
        f.write(b'</spectrumList>\n</run>\n</mzML>\n')
    print('%s: %d spectra' % (out, len(blocks)))


if __name__ == '__main__':
    main()
