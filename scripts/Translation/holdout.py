"""Build the evaluation holdout: Skyline 25.1 strings with the translator's pre-review draft
(archive localization.<lang>-LS.csv) and the reviewed final (current checked-in RESX value).

holdout.py <session dir>
Writes eval/holdout.<lang>.tsv  (name, en, ls_draft, final)
       eval/blind-input.<lang>.tsv (id, en)          <- the only thing the blind translator sees
       eval/tm-excluding-holdout.tsv (en, ja, zh)     <- corpus minus every holdout English string
"""
import csv
import os
import sys

sd = sys.argv[1]
os.makedirs(os.path.join(sd, 'eval'), exist_ok=True)


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


def esc(s):
    return (s or '').replace('\\', '\\\\').replace('\t', '\\t').replace('\r\n', '\\n').replace('\n', '\\n')


corpus = []
with open(os.path.join(sd, 'corpus-resx.tsv'), encoding='utf-8') as f:
    next(f)
    for line in f:
        file, key, en, ja, zh = line.rstrip('\n').split('\t')
        corpus.append((key, unesc(en), unesc(ja), unesc(zh)))
by_key_en = {}
by_en = {}
for key, en, ja, zh in corpus:
    by_key_en[(key, en)] = (ja, zh)
    by_en.setdefault(en, set()).add((ja, zh))

def read_rows(rel):
    path = os.path.join(sd, rel)
    if rel.endswith('.tsv'):
        lines = [l.rstrip('\n').split('\t') for l in open(path, encoding='utf-8')]
        head = lines[0]
        return [{h: unesc(c[i]) if i < len(c) else '' for i, h in enumerate(head) if h not in ('Comment',)}
                for c in lines[1:]]
    return list(csv.DictReader(open(path, encoding='utf-8-sig')))


SRC = {'ja': (['archive/ja/25_1/localization.ja-LS.csv',
               'archive/ja/24_1/localization.ja_MI_KS.localization.ja_JA-JP.tsv'], 0),
       'zh': (['archive/zh/25_1/localization.zh-CHS-LS.csv',
               'archive/zh/24_1/localization.zh-CHS_MGH.csv'], 1)}
holdout_en = set()
for lang, (rels, li) in SRC.items():
    rows = []
    seen_en = set()
    for rel in rels:
        for r in read_rows(rel):
            if r['English'] not in seen_en:  # 25.1 wins where both rounds carry a string
                seen_en.add(r['English'])
                rows.append(r)
    kept = 0
    skipped = {'no draft': 0, 'no final': 0, 'final is English': 0}
    with open(os.path.join(sd, 'eval', 'holdout.%s.tsv' % lang), 'w', encoding='utf-8', newline='') as out, \
            open(os.path.join(sd, 'eval', 'blind-input.%s.tsv' % lang), 'w', encoding='utf-8', newline='') as blind:
        out.write('id\tname\ten\tls_draft\tfinal\n')
        blind.write('id\ten\n')
        for r in rows:
            en, draft, name = r['English'], r['Translation'], r['Name']
            if not draft.strip():
                skipped['no draft'] += 1
                continue
            fin = by_key_en.get((name, en))
            if fin is None and len(by_en.get(en, ())) == 1:
                fin = next(iter(by_en[en]))
            if fin is None or not fin[li]:
                skipped['no final' if fin is None else 'final is English'] += 1
                continue
            kept += 1
            rid = '%s%03d' % (lang, kept)
            out.write('\t'.join([rid, name, esc(en), esc(draft), esc(fin[li])]) + '\n')
            blind.write('\t'.join([rid, esc(en)]) + '\n')
            holdout_en.add(en)
    print(lang, 'holdout', kept, 'skipped', skipped)

with open(os.path.join(sd, 'eval', 'tm-excluding-holdout.tsv'), 'w', encoding='utf-8', newline='') as f:
    f.write('en\tja\tzh\n')
    n = 0
    for key, en, ja, zh in corpus:
        if en in holdout_en:
            continue
        f.write('\t'.join([esc(en), esc(ja), esc(zh)]) + '\n')
        n += 1
print('tm rows', n, 'excluded english strings', len(holdout_en))
