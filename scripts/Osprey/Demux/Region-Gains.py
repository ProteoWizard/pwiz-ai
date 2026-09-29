"""Where across precursor m/z and retention time does one DIA-NN arm gain or lose target precursors
against another (Q.Value <= 0.01, non-entrapment)?

Usage: python Region-Gains.py <base report.parquet> <arm report.parquet>
"""
import sys

import numpy as np
import pandas as pd


def load(path):
    df = pd.read_parquet(path, columns=['Precursor.Id', 'Precursor.Mz', 'RT', 'Q.Value', 'Protein.Ids'])
    return df[(df['Q.Value'] <= 0.01) & ~df['Protein.Ids'].str.contains('_p_target', regex=False)]


def main():
    base, arm = load(sys.argv[1]), load(sys.argv[2])
    mz_edges = [390, 500, 600, 700, 800, 910]
    rt_edges = [0, 2, 4, 6, 8, 10, 20]
    print('rows: precursor m/z; columns: RT (min); cells: arm / base target precursors (arm - base)')
    print('%-10s' % 'm/z \\ RT' + ''.join('%18s' % ('%g-%g' % (rt_edges[i], rt_edges[i + 1])) for i in range(len(rt_edges) - 1)))
    for i in range(len(mz_edges) - 1):
        line = '%-10s' % ('%d-%d' % (mz_edges[i], mz_edges[i + 1]))
        for j in range(len(rt_edges) - 1):
            def count(df):
                return int(((df['Precursor.Mz'] >= mz_edges[i]) & (df['Precursor.Mz'] < mz_edges[i + 1]) &
                            (df['RT'] >= rt_edges[j]) & (df['RT'] < rt_edges[j + 1])).sum())
            a, b = count(arm), count(base)
            line += '%18s' % ('%d/%d (%+d)' % (a, b, a - b))
        print(line)


if __name__ == '__main__':
    main()
