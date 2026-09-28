"""Line-by-line diff of two mzML files written by the demux tool: the number of differing lines and the
first few, ignoring the index footer (its offsets move with any header change).

Usage: python Diff-Mzml.py <a.mzML> <b.mzML>
"""
import sys


def main():
    differing = 0
    shown = 0
    with open(sys.argv[1], encoding='utf-8') as a, open(sys.argv[2], encoding='utf-8') as b:
        for n, (x, y) in enumerate(zip(a, b), 1):
            if x.lstrip().startswith(('<offset', '<indexListOffset', '<fileChecksum')):
                continue
            if x != y:
                differing += 1
                if shown < 5:
                    print('line %d:\n  a: %s\n  b: %s' % (n, x.strip()[:200], y.strip()[:200]))
                    shown += 1
        rest_a = sum(1 for _ in a)
        rest_b = sum(1 for _ in b)
    print('differing lines: %d; lines left over: a %d, b %d' % (differing, rest_a, rest_b))


if __name__ == '__main__':
    main()
