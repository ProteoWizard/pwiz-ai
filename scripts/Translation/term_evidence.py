"""Glossary evidence per English term.

term_evidence.py <session dir> <terms.txt> <out.md>

terms.txt: one English term per line; optional ' | cand1 ; cand2' (ja) and ' || cand1 ; cand2' (zh)
candidate renderings to measure in addition to the archive glossary's.

For each term: occurrence count in <session dir>/inventory.tsv (from resx_inventory.py); archive renderings (ja 2016 term base + 2014 glossary, zh
2014-06-03 + 05-23 reviewed); and for every candidate rendering, the share of reviewed RESX and
tutorial pairs whose English contains the term and whose translation contains that rendering.
Also the shortest few RESX pairs as examples, so a human (or Claude) can see the usage directly.
"""
import csv
import os
import re
import sys


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


def load_glossary(path, en_col, loc_col, skip=1):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding='utf-8') as f:
        for i, line in enumerate(f):
            if i < skip:
                continue
            c = line.rstrip('\n').split('\t')
            if len(c) > max(en_col, loc_col) and c[en_col].strip() and c[loc_col].strip():
                out.setdefault(c[en_col].strip().lower(), []).append(c[loc_col].strip())
    return out


def term_re(term):
    return re.compile(r'(?<![A-Za-z])' + re.escape(term) + r's?(?![A-Za-z])', re.I)


def main():
    sd, terms_path, out_path = sys.argv[1:4]
    a = os.path.join(sd, 'archive')
    gl = {
        'ja': [('termbase2016', load_glossary(os.path.join(a, 'ja', 'termbase_2016-04_latest.terms.tsv'), 0, 1)),
               ('gloss2014', load_glossary(os.path.join(a, 'ja', 'glossary_72177_2014-01-15.Sheet1.tsv'), 0, 1))],
        'zh': [('gloss2014-06', load_glossary(os.path.join(a, 'zh', 'glossary_2014-06-03.terms.tsv'), 0, 1)),
               ('gloss2014-05rev', load_glossary(os.path.join(a, 'zh', 'glossary_2014-05-23_final_reviewed.terms.tsv'), 0, 1))],
    }
    resx = []
    with open(os.path.join(sd, 'corpus-resx.tsv'), encoding='utf-8') as f:
        next(f)
        for line in f:
            file, key, en, ja, zh = line.rstrip('\n').split('\t')
            resx.append((unesc(en), unesc(ja), unesc(zh)))
    tut = {'ja': [], 'zh': []}
    with open(os.path.join(sd, 'corpus-tutorials.tsv'), encoding='utf-8') as f:
        next(f)
        for line in f:
            t, lang, xp, en, loc = line.rstrip('\n').split('\t')
            tut[lang].append((en, loc))
    osprey = []
    with open(os.path.join(sd, 'inventory.tsv'), encoding='utf-8') as f:
        next(f)
        for line in f:
            osprey.append(unesc(line.split('\t')[2]))

    out = []
    for raw in open(terms_path, encoding='utf-8'):
        raw = raw.rstrip('\n')
        if not raw.strip() or raw.startswith('#'):
            continue
        term, _, rest = raw.partition(' | ')
        ja_extra, _, zh_extra = rest.partition(' || ')
        term = term.strip()
        extra = {'ja': [x.strip() for x in ja_extra.split(';') if x.strip()],
                 'zh': [x.strip() for x in zh_extra.split(';') if x.strip()]}
        rx = term_re(term)
        n_osp = sum(1 for e in osprey if rx.search(e))
        out.append('## %s   (project: %d)' % (term, n_osp))
        for li, lang in ((1, 'ja'), (2, 'zh')):
            hits = [r for r in resx if rx.search(r[0]) and r[li]]
            thits = [p for p in tut[lang] if rx.search(p[0])]
            cands = []
            for name, g in gl[lang]:
                for v in g.get(term.lower(), []):
                    cands.append((v, name))
            for v in extra[lang]:
                cands.append((v, 'proposed'))
            seen = set()
            parts = []
            for v, src in cands:
                if v in seen:
                    continue
                seen.add(v)
                r = sum(1 for h in hits if v in h[li])
                t = sum(1 for p in thits if v in p[1])
                parts.append('`%s` [%s] resx %d/%d, tut %d/%d' % (v, src, r, len(hits), t, len(thits)))
            out.append('- %s: %s' % (lang, '; '.join(parts) if parts else '(no candidates) resx n=%d tut n=%d' % (len(hits), len(thits))))
            ex = sorted(hits, key=lambda h: len(h[0]))[:4]
            for h in ex:
                out.append('    - `%s` -> `%s`' % (h[0].replace('\n', ' ')[:90], h[li].replace('\n', ' ')[:90]))
        out.append('')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print(len([l for l in out if l.startswith('## ')]), 'terms')


if __name__ == '__main__':
    main()
