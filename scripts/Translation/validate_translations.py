"""Mechanical and consistency checks over a translation table - the checks a translation company's
consistency review would do, run before anything goes to the expert reviewers.

validate_translations.py <table.tsv> <glossary.tsv> [report.md]

table.tsv columns: file, key, en, ja, zh (escaped: \\n \\t \\\\); extra columns are ignored.
Hard failures (exit 1): placeholder set differs, Error:/Warning: prefix wrong, empty translation.
Findings (reported, not failing): style-guide deviations, glossary non-conformance, the same English
translated differently, ASCII runs that look like leaked English.
"""
import collections
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
PH = re.compile(r'\{\d+(?::[^}]*)?\}')
CJK = r'[぀-ヿ㐀-鿿]'
PREFIX = {'ja': {'Error:': 'エラー：', 'Warning:': '警告：'},
          'zh': {'Error:': '错误：', 'Warning:': '警告：'}}
# tokens that legitimately stay in English inside a translation
KEEP = set('''Osprey Skyline Percolator Mokapot BiblioSpec DIA-NN DIA DDA ProteoWizard msconvert mzML Parquet
parquet JSON SVM LDA LOESS FDR PEP RT MS1 MS2 MS/MS m/z ppm CV TSV CSV HRAM Carafe EncyclopeDIA FDRBench GB MB
Th C NaN ID IDs CPU SQLite blib elib R2 log10 Q q'''.split())


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


def load_glossary(path):
    rows = []
    for i, line in enumerate(open(path, encoding='utf-8')):
        if i == 0:
            continue
        c = line.rstrip('\n').split('\t')
        term = re.sub(r'\s*\(.*?\)', '', c[0]).strip()
        if not term or term.endswith(':'):
            continue
        for t in term.split(' / '):
            rx = re.compile(r'(?<![A-Za-z-])' + re.escape(t.strip()) + r'(s|es)?(?![A-Za-z-])', re.I)
            rows.append((t.strip(), rx, {'ja': [x.strip() for x in c[1].split(' / ')],
                                         'zh': [x.strip() for x in c[2].split(' / ')]}, c[3]))
    # longest terms first so "precursor candidate peak" is checked before "peak"
    rows.sort(key=lambda r: -len(r[0]))
    return rows


def style_findings(lang, en, t):
    out = []
    if re.search(r'[a-z)]\.$', en.strip()) and not t.strip().endswith('。'):
        out.append('sentence should end with 。')
    if re.search(r'\w:$', en.strip()) and not t.strip().endswith('：'):
        out.append('trailing colon should be ：')
    if re.search(r"'\{\d+\}'", en):
        want = r'「\{\d+\}」' if lang == 'ja' else r'“\{\d+\}”'
        if not re.search(want, t):
            out.append('quoted placeholder should be ' + ('「{n}」' if lang == 'ja' else '“{n}”'))
    if en.rstrip().endswith('...'):
        want = '...' if lang == 'ja' else '…'
        if not t.rstrip().endswith(want):
            out.append('trailing ellipsis should be ' + want)
    if lang == 'ja':
        n = len(re.findall(CJK + r' [A-Za-z0-9{]', t)) + len(re.findall(r'[A-Za-z0-9}] ' + CJK, t))
        if n:
            out.append('ja: no space between CJK and Latin/digits/placeholders (%d)' % n)
        if '，' in t:
            out.append('ja: use 、 not ，')
    else:
        n = len(re.findall(CJK + r'[A-Za-z0-9]', t)) + len(re.findall(r'[A-Za-z0-9]' + CJK, t))
        if n:
            out.append('zh: space between CJK and Latin/digits (%d)' % n)
        if '、' in t and ',' in en and '、' not in t.replace('、', '', 1):
            pass
    if re.search(r'[—–]', t):
        out.append('em/en dash')
    return out


def leaked_english(en, t):
    words = [w for w in re.findall(r"[A-Za-z][A-Za-z'-]{3,}", t) if w not in KEEP and w.lower() not in (k.lower() for k in KEEP)]
    en_words = set(re.findall(r"[A-Za-z][A-Za-z'-]{3,}", en))
    # an English word copied from the source that is not a keep-token is suspicious
    return sorted(set(w for w in words if w in en_words))


def main():
    table, gpath = sys.argv[1], sys.argv[2]
    report = sys.argv[3] if len(sys.argv) > 3 else None
    gloss = load_glossary(gpath)
    rows = []
    for i, line in enumerate(open(table, encoding='utf-8')):
        if i == 0:
            continue
        c = line.rstrip('\n').split('\t')
        rows.append((c[0], c[1], unesc(c[2]), unesc(c[3]) if len(c) > 3 else '', unesc(c[4]) if len(c) > 4 else ''))
    hard = []
    finds = collections.defaultdict(list)
    by_en = {'ja': collections.defaultdict(set), 'zh': collections.defaultdict(set)}
    gstat = {'ja': [0, 0], 'zh': [0, 0]}
    for file, key, en, ja, zh in rows:
        for lang, t in (('ja', ja), ('zh', zh)):
            where = '%s %s [%s]' % (file.split('/')[-1], key, lang)
            if not t.strip():
                hard.append('%s: empty translation' % where)
                continue
            if sorted(PH.findall(t)) != sorted(PH.findall(en)):
                hard.append('%s: placeholders %s vs English %s' % (where, sorted(PH.findall(t)), sorted(PH.findall(en))))
            for p, want in PREFIX[lang].items():
                if en.startswith(p) and not t.startswith(want):
                    hard.append('%s: must start with %s' % (where, want))
                if not en.startswith(p) and t.startswith(want):
                    hard.append('%s: starts with %s but English does not' % (where, want))
            for s in style_findings(lang, en, t):
                finds['style'].append('%s: %s' % (where, s))
            # glossary: a matched English term must use one of its renderings, unless a longer
            # term containing it already matched the same span
            covered = []
            for term, rx, rend, status in gloss:
                for m in rx.finditer(en):
                    if any(a <= m.start() and m.end() <= b for a, b in covered):
                        continue
                    covered.append((m.start(), m.end()))
                    gstat[lang][0] += 1
                    opts = [r for r in rend[lang] if r]
                    if any(o in t for o in opts):
                        gstat[lang][1] += 1
                    else:
                        finds['glossary'].append('%s: "%s" -> expected %s (%s)' % (where, term, ' or '.join(opts), status))
            lk = leaked_english(en, t)
            if lk:
                finds['leaked-english'].append('%s: %s' % (where, ', '.join(lk)))
            by_en[lang][en].add(t)
    for lang in ('ja', 'zh'):
        for en, ts in by_en[lang].items():
            if len(ts) > 1:
                finds['inconsistent'].append('[%s] "%s" -> %s' % (lang, en[:80], ' | '.join(sorted(ts))))
    out = ['# Translation validation: %s' % table, '',
           '%d strings; hard failures %d' % (len(rows), len(hard)),
           'glossary conformance: ja %d/%d, zh %d/%d' % (gstat['ja'][1], gstat['ja'][0], gstat['zh'][1], gstat['zh'][0]), '']
    if hard:
        out += ['## Hard failures'] + ['- ' + h for h in hard] + ['']
    for k in ('inconsistent', 'glossary', 'style', 'leaked-english'):
        out += ['## %s (%d)' % (k, len(finds[k]))] + ['- ' + f for f in finds[k]] + ['']
    text = '\n'.join(out)
    if report:
        open(report, 'w', encoding='utf-8').write(text)
        print('\n'.join(out[:5]))
        for k in ('inconsistent', 'glossary', 'style', 'leaked-english'):
            print('%s: %d' % (k, len(finds[k])))
    else:
        print(text)
    sys.exit(1 if hard else 0)


if __name__ == '__main__':
    main()
