"""Every resource whose draft differs from the English must appear in the reviewer CSVs.

check_coverage.py <drafts both.tsv> <reviewer package dir> [project=Osprey]
"""
import csv
import os
import sys


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


both, pkg = sys.argv[1], sys.argv[2]
project = sys.argv[3] if len(sys.argv) > 3 else 'Osprey'
rows = [l.rstrip('\n').split('\t') for l in open(both, encoding='utf-8')][1:]
for lang, col in (('ja', 3), ('zh-Hans', 4)):
    need = set(unesc(r[2]) for r in rows if r[col] != r[2])
    got = set(r['English'] for r in csv.DictReader(open(os.path.join(pkg, '%s-localization.%s.csv' % (project.lower(), lang)), encoding='utf-8-sig')))
    print(lang, 'distinct English to review', len(need), 'covered', len(need & got), 'missing', len(need - got))
