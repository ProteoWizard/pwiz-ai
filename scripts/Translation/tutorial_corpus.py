"""Tutorial parallel corpus, aligned the way DevTools/TutorialLocalization does it: each translated
tutorial's <lang>/invariant.html is the English the translator saw and <lang>/index.html its
translation, XPath-parallel. (The tool itself fails on the port branch: its lib CsvHelper.dll needs
Microsoft.Bcl.HashCode, which the net10 output no longer carries.)

tutorial_corpus.py <Tutorials dir> <out.tsv>
Columns: tutorial, lang (ja|zh), xpath, en, loc   (text content, whitespace-normalized)
"""
import os
import re
import sys

import lxml.html

LOCALIZABLE = {'/html/head/title', '/html/body/p', '/html/body/h1', '/html/body/h2', '/html/body/ul/li',
               '/html/body/ol/li', '/html/body/table/tr/td', '/html/body/div/table/tr/td'}
LANG_DIRS = {'ja': 'ja', 'zh': 'zh-CHS'}


def norm(s):
    return re.sub(r'\s+', ' ', s or '').strip()


def elements(doc):
    tree = doc.getroottree()
    for el in doc.iter():
        if not isinstance(el.tag, str):
            continue
        xp = tree.getpath(el)
        if re.sub(r'\[\d+\]', '', xp) in LOCALIZABLE:
            yield xp, el


def main():
    root, out_path = sys.argv[1], sys.argv[2]
    n = {'ja': 0, 'zh': 0}
    with open(out_path, 'w', encoding='utf-8', newline='') as f:
        f.write('tutorial\tlang\txpath\ten\tloc\n')
        for tut in sorted(os.listdir(root)):
            for lang, d in LANG_DIRS.items():
                inv = os.path.join(root, tut, d, 'invariant.html')
                loc = os.path.join(root, tut, d, 'index.html')
                if not (os.path.exists(inv) and os.path.exists(loc)):
                    continue
                inv_doc = lxml.html.parse(inv).getroot()
                loc_doc = lxml.html.parse(loc).getroot()
                loc_tree = loc_doc.getroottree()
                loc_by_xpath = {loc_tree.getpath(e): e for e in loc_doc.iter() if isinstance(e.tag, str)}
                for xp, el in elements(inv_doc):
                    le = loc_by_xpath.get(xp)
                    if le is None:
                        continue
                    en, lt = norm(el.text_content()), norm(le.text_content())
                    if not en or not lt or en == lt:
                        continue
                    f.write('\t'.join([tut, lang, xp, en.replace('\t', ' '), lt.replace('\t', ' ')]) + '\n')
                    n[lang] += 1
    print(n)


if __name__ == '__main__':
    main()
