"""Measure punctuation and spacing conventions in the reviewed Skyline translations, so the style
guide is derived from what reviewers accepted rather than invented.

style_stats.py <corpus-resx.tsv>
"""
import re
import sys

CJK = r'[\u3040-\u30ff\u3400-\u9fff]'


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


rows = []
with open(sys.argv[1], encoding='utf-8') as f:
    next(f)
    for line in f:
        file, key, en, ja, zh = line.rstrip('\n').split('\t')
        rows.append((unesc(en), unesc(ja), unesc(zh)))


def pct(a, b):
    return '%d/%d (%.0f%%)' % (a, b, 100.0 * a / b if b else 0)


def measure(name, li):
    pairs = [(r[0], r[li]) for r in rows if r[li]]
    print('=== %s (%d pairs)' % (name, len(pairs)))
    # 1. colon after text, where English has ':' at end or 'X: {0}'
    en_colon = [(e, t) for e, t in pairs if re.search(r'\w:\s', e + ' ')]
    print('colon: full-width \uff1a', pct(sum('\uff1a' in t for e, t in en_colon), len(en_colon)),
          '| ascii :', pct(sum(re.search(r'[^:]:(?!/)', t) is not None and '\uff1a' not in t for e, t in en_colon), len(en_colon)))
    # 2. sentence end: English ends with '.', translation ends with '\u3002'
    en_dot = [(e, t) for e, t in pairs if re.search(r'[a-z)]\.$', e.strip())]
    print('sentence end \u3002', pct(sum(t.strip().endswith('\u3002') for e, t in en_dot), len(en_dot)),
          '| ascii .', pct(sum(t.strip().endswith('.') for e, t in en_dot), len(en_dot)))
    # 3. quotes around a quoted placeholder: English '{0}' or "{0}"
    q = [(e, t) for e, t in pairs if re.search(r"['\"]\{\d+\}['\"]", e)]
    for label, rx in (('\u300c{n}\u300d', r'\u300c\{\d+\}\u300d'), ('\u201c{n}\u201d', r'\u201c\{\d+\}\u201d'),
                      ("'{n}'", r"'\{\d+\}'"), ('"{n}"', r'"\{\d+\}"'), ('bare {n}', None)):
        if rx:
            n = sum(re.search(rx, t) is not None for e, t in q)
        else:
            n = sum(re.search(r"[\u300c\u201c'\"]\{\d+\}", t) is None for e, t in q)
        print('  quoted placeholder as %s:' % label, pct(n, len(q)))
    # 4. spacing between CJK and a placeholder / Latin word / digit
    cjk_ph = sum(len(re.findall(CJK + r'\{\d', t)) + len(re.findall(r'\}' + CJK, t)) for e, t in pairs)
    cjk_sp_ph = sum(len(re.findall(CJK + r' \{\d', t)) + len(re.findall(r'\} ' + CJK, t)) for e, t in pairs)
    print('CJK<->{n} adjacency: no space %d, with space %d' % (cjk_ph, cjk_sp_ph))
    cjk_lat = sum(len(re.findall(CJK + r'[A-Za-z0-9]', t)) + len(re.findall(r'[A-Za-z0-9]' + CJK, t)) for e, t in pairs)
    cjk_sp_lat = sum(len(re.findall(CJK + r' [A-Za-z0-9]', t)) + len(re.findall(r'[A-Za-z0-9] ' + CJK, t)) for e, t in pairs)
    print('CJK<->Latin/digit adjacency: no space %d, with space %d' % (cjk_lat, cjk_sp_lat))
    # 5. parentheses
    par = [(e, t) for e, t in pairs if '(' in e and '{' not in e.split('(')[1][:1]]
    print('parens: full-width \uff08', pct(sum('\uff08' in t for e, t in par), len(par)),
          '| ascii (', pct(sum('(' in t and '\uff08' not in t for e, t in par), len(par)))
    # 6. ellipsis
    el = [(e, t) for e, t in pairs if e.rstrip().endswith('...')]
    print('ellipsis: ...', pct(sum(t.rstrip().endswith('...') for e, t in el), len(el)),
          '| \u2026', pct(sum(t.rstrip().endswith('\u2026') for e, t in el), len(el)),
          '| \u2026\u2026', pct(sum(t.rstrip().endswith('\u2026\u2026') for e, t in el), len(el)))
    # 7. comma
    cm = [(e, t) for e, t in pairs if ', ' in e and len(e) > 30]
    print('comma: \u3001', pct(sum('\u3001' in t for e, t in cm), len(cm)), '| \uff0c', pct(sum('\uff0c' in t for e, t in cm), len(cm)),
          '| ascii ,', pct(sum(',' in t for e, t in cm), len(cm)))
    # 8. percent and number formats kept
    pf = [(e, t) for e, t in pairs if re.search(r'\{\d+:[^}]+\}', e)]
    print('format specifiers preserved verbatim:', pct(sum(all(s in t for s in re.findall(r'\{\d+:[^}]+\}', e)) for e, t in pf), len(pf)))
    # 9. "Error:" style prefixes
    for word in ('Error:', 'Warning:'):
        ex = [(e, t) for e, t in pairs if e.startswith(word)]
        heads = {}
        for e, t in ex:
            h = re.match(r'^[^\s{]{1,6}[\uff1a:]', t)
            k = h.group(0) if h else t[:6]
            heads[k] = heads.get(k, 0) + 1
        print('  %s ->' % word, sorted(heads.items(), key=lambda kv: -kv[1])[:5])
    # 10. "Failed to X" and "Unable to X" and progress "-ing..." patterns
    ing = [(e, t) for e, t in pairs if re.match(r'^[A-Z][a-z]+ing\b', e) and e.rstrip().endswith('...')]
    print('progress "Xing..." examples:', [t for e, t in ing[:6]])


measure('ja', 1)
measure('zh', 2)
