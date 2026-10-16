"""Inventory a project's English resources and their exact-match coverage in the reviewed corpus.

resx_inventory.py <pwiz root> <project dir, e.g. pwiz_tools/Osprey> <corpus.tsv> <out.tsv>

Scans every English .resx (no culture suffix) under the project directory, skipping bin/obj.

Columns: file, key, en, comment, tm_ja, tm_zh (exact-match reviewed translation, if any).
"""
import glob
import re
import os
import sys
import xml.etree.ElementTree as ET


def unesc(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '\\': '\\'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def esc(s):
    return (s or '').replace('\\', '\\\\').replace('\t', '\\t').replace('\r\n', '\\n').replace('\n', '\\n')


def load_corpus(path):
    tm = {'ja': {}, 'zh': {}}
    with open(path, encoding='utf-8') as f:
        next(f)
        for line in f:
            file, key, en, ja, zh = line.rstrip('\n').split('\t')
            for lang, v in (('ja', ja), ('zh', zh)):
                if v:
                    tm[lang].setdefault(unesc(en), {}).setdefault(unesc(v), 0)
                    tm[lang][unesc(en)][unesc(v)] += 1
    return tm


def main():
    root, project, corpus, out_path = sys.argv[1:5]
    tm = load_corpus(corpus)
    files = sorted(p for p in glob.glob(os.path.join(root, project, '**', '*.resx'), recursive=True)
                   if os.path.basename(p).count('.') == 1
                   and not re.search(r'[\\/](bin|obj)[\\/]', p))
    hits = {'ja': 0, 'zh': 0}
    total = 0
    with open(out_path, 'w', encoding='utf-8', newline='') as f:
        f.write('file\tkey\ten\tcomment\ttm_ja\ttm_zh\n')
        for p in files:
            rel = os.path.relpath(p, root).replace('\\', '/')
            for d in ET.parse(p).getroot().iter('data'):
                v = d.find('value')
                c = d.find('comment')
                en = v.text or ''
                cells = [rel, d.get('name'), esc(en), esc(c.text if c is not None else '')]
                for lang in ('ja', 'zh'):
                    cands = tm[lang].get(en, {})
                    best = max(cands, key=cands.get) if cands else ''
                    if best:
                        hits[lang] += 1
                    # more than one reviewed rendering of the same English is a consistency signal
                    cells.append(esc(best) + (' [+%d alt]' % (len(cands) - 1) if len(cands) > 1 else ''))
                f.write('\t'.join(cells) + '\n')
                total += 1
    print(total, 'resources; exact TM hits', hits)


if __name__ == '__main__':
    main()
