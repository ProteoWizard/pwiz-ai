"""Build the reviewers' CSVs: the rows GenerateLocalizationCsvFiles wrote for Osprey, in the
translation company's format, plus three columns the import ignores - Claude's confidence, its note
to the reviewer, and the glossary terms in the English with the rendering the glossary requires.

reviewer_package.py <Scratch dir> <drafts both.tsv> <glossary.tsv> <out dir> [project=Osprey]
The project name filters the CSV rows by their File column and names the output files.
Rows are sorted low -> medium -> high confidence, so reviewers see the doubtful ones first.
"""
import csv
import os
import re
import sys

scratch, both, gpath, out = sys.argv[1:5]
project = sys.argv[5] if len(sys.argv) > 5 else 'Osprey'
os.makedirs(out, exist_ok=True)


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


meta = {}
by_en = {}
for i, line in enumerate(open(both, encoding='utf-8')):
    if i == 0:
        continue
    c = line.rstrip('\n').split('\t')
    meta[(c[1], unesc(c[2]))] = {'ja': (c[5], c[7]), 'zh-Hans': (c[6], c[8])}
    # the export consolidates identical English across files into one row with an empty Name
    by_en.setdefault(unesc(c[2]), meta[(c[1], unesc(c[2]))])


def lookup(r):
    if r['Name']:
        return meta.get((r['Name'], r['English']))
    return by_en.get(r['English']) if project in r['File'] else None

gloss = []
for i, line in enumerate(open(gpath, encoding='utf-8')):
    if i == 0:
        continue
    c = line.rstrip('\n').split('\t')
    term = re.sub(r'\s*\(.*?\)', '', c[0]).strip()
    if term and not term.endswith(':'):
        gloss.append((term, re.compile(r'(?<![A-Za-z-])' + re.escape(term) + r'(s|es)?(?![A-Za-z-])', re.I),
                      {'ja': c[1], 'zh-Hans': c[2]}, c[3]))
gloss.sort(key=lambda g: -len(g[0]))

ORDER = {'low': 0, 'medium': 1, 'high': 2, '': 3}
for lang in ('ja', 'zh-Hans'):
    src = os.path.join(scratch, 'localization.%s.csv' % lang)
    rows = list(csv.DictReader(open(src, encoding='utf-8-sig')))
    cols = list(rows[0].keys())
    osprey = [r for r in rows if lookup(r)]
    for r in osprey:
        conf, note = lookup(r)[lang]
        r['Claude confidence'] = conf
        r['Claude note'] = note
        spans, terms = [], []
        for term, rx, rend, status in gloss:
            for m in rx.finditer(r['English']):
                if any(a <= m.start() and m.end() <= b for a, b in spans):
                    continue
                spans.append((m.start(), m.end()))
                t = '%s = %s%s' % (term, rend[lang], '' if status == 'reviewed' else ' (new)')
                if t not in terms:
                    terms.append(t)
        r['Glossary terms'] = '; '.join(terms)
    osprey.sort(key=lambda r: (ORDER.get(r['Claude confidence'], 3), r['File'], r['Name']))
    dst = os.path.join(out, '%s-localization.%s.csv' % (project.lower(), lang))
    with open(dst, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols + ['Claude confidence', 'Claude note', 'Glossary terms'])
        w.writeheader()
        w.writerows(osprey)
    counts = {k: sum(1 for r in osprey if r['Claude confidence'] == k) for k in ('low', 'medium', 'high')}
    print(dst, len(osprey), 'rows of', len(rows), counts)
