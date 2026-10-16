"""Show reviewed pairs whose English matches a regex (case-insensitive), from both corpora.

grep_pairs.py <regex> [max per source=15] [lang ja|zh|both]
"""
import re
import sys

rx = re.compile(sys.argv[1], re.I)
mx = int(sys.argv[2]) if len(sys.argv) > 2 else 15
lang = sys.argv[3] if len(sys.argv) > 3 else 'both'
sys.stdout.reconfigure(encoding='utf-8')


def unesc(s):
    return s.replace('\\n', ' ').replace('\\t', ' ').replace('\\\\', '\\')


n = 0
print('--- resx')
for line in open('corpus-resx.tsv', encoding='utf-8'):
    file, key, en, ja, zh = line.rstrip('\n').split('\t')
    if rx.search(en):
        print('EN:', unesc(en)[:160])
        if lang in ('ja', 'both') and ja:
            print('JA:', unesc(ja)[:160])
        if lang in ('zh', 'both') and zh:
            print('ZH:', unesc(zh)[:160])
        n += 1
        if n >= mx:
            break
n = 0
print('--- tutorials')
for line in open('corpus-tutorials.tsv', encoding='utf-8'):
    t, lg, xp, en, loc = line.rstrip('\n').split('\t')
    if (lang == 'both' or lg == lang) and rx.search(en):
        m = rx.search(en)
        s = max(0, m.start() - 60)
        print('%s EN: ...%s...' % (lg, en[s:m.end() + 80]))
        print('%s    : %s' % (lg, loc[:200]))
        n += 1
        if n >= mx:
            break
