# Compares two BiblioSpec .blib files table by table, row by row, including blobs. LibInfo's
# createTime (the write time) is the only column allowed to differ.
# Usage: compare_blib.py <a.blib> <b.blib>
import hashlib
import sqlite3
import sys

IGNORE = {('LibInfo', 'createTime')}


def tables(con):
    return sorted(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))


def digest(con, table):
    cols = [r[1] for r in con.execute('PRAGMA table_info([%s])' % table)]
    keep = [c for c in cols if (table, c) not in IGNORE]
    order = ', '.join('[%s]' % c for c in keep)
    h = hashlib.sha256()
    n = 0
    for row in con.execute('SELECT %s FROM [%s] ORDER BY %s' % (order, table, order)):
        h.update(repr(row).encode('utf-8'))
        n += 1
    return cols, n, h.hexdigest()


def main():
    a, b = sqlite3.connect(sys.argv[1]), sqlite3.connect(sys.argv[2])
    ta, tb = tables(a), tables(b)
    ok = ta == tb
    if not ok:
        print('TABLE SETS DIFFER:', ta, tb)
    for t in sorted(set(ta) & set(tb)):
        ca, na, ha = digest(a, t)
        cb, nb, hb = digest(b, t)
        same = ca == cb and na == nb and ha == hb
        ok &= same
        print('%-28s %10d rows  %s' % (t, na, 'identical' if same else 'DIFFERENT (b has %d rows)' % nb))
    ia = sorted(r for r in a.execute("SELECT name, sql FROM sqlite_master WHERE type='index'"))
    ib = sorted(r for r in b.execute("SELECT name, sql FROM sqlite_master WHERE type='index'"))
    print('indexes', 'identical' if ia == ib else 'DIFFERENT')
    ok &= ia == ib
    print('RESULT:', 'IDENTICAL' if ok else 'DIFFERENT')
    sys.exit(0 if ok else 1)


main()
