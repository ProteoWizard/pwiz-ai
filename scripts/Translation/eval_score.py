"""Score Claude's blind drafts and the professional (LS) drafts against the reviewed finals.

eval_score.py <session dir> <lang ja|zh> [out.md]
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
sd, lang = sys.argv[1], sys.argv[2]
out_path = sys.argv[3] if len(sys.argv) > 3 else None


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


def lev(a, b):
    if a == b:
        return 0
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def sim(a, b):
    m = max(len(a), len(b))
    return 1.0 - lev(a, b) / m if m else 1.0


PH = re.compile(r'\{\d+(?::[^}]*)?\}')

hold = {}
for line in list(open(os.path.join(sd, 'eval', 'holdout.%s.tsv' % lang), encoding='utf-8'))[1:]:
    rid, name, en, ls, fin = line.rstrip('\n').split('\t')
    hold[rid] = (unesc(en), unesc(ls), unesc(fin))
claude = {}
for line in list(open(os.path.join(sd, 'eval-blind', 'claude.%s.tsv' % lang), encoding='utf-8'))[1:]:
    c = line.rstrip('\n').split('\t')
    claude[c[0]] = (unesc(c[1]), c[2] if len(c) > 2 else '', c[3] if len(c) > 3 else '')

# glossary: reviewed rows only, English term -> required rendering (first alternative)
gcol = {'ja': 1, 'zh': 2}[lang]
gloss = []
for line in list(open(os.path.join(sd, 'eval-blind', 'glossary.tsv'), encoding='utf-8'))[1:]:
    c = line.rstrip('\n').split('\t')
    if c[3] != 'reviewed':
        continue
    term = re.sub(r'\s*\(.*?\)', '', c[0]).strip()
    if not term or term.endswith(':') or '/' in term:
        continue
    render = c[gcol].split(' / ')[0].strip()
    gloss.append((re.compile(r'(?<![A-Za-z])' + re.escape(term) + r's?(?![A-Za-z])', re.I), term, render))


def gloss_hits(en, t):
    n = ok = 0
    for rx, term, render in gloss:
        if rx.search(en):
            n += 1
            ok += render in t
    return n, ok


CJK = r'[぀-ヿ㐀-鿿]'


def style_checks(en, t):
    """(applicable, passed) counts for the measurable style-guide rules."""
    res = []
    if re.search(r'[a-z)]\.$', en.strip()):
        res.append(t.strip().endswith('。'))
    if re.search(r"'\{\d+\}'", en):
        res.append(re.search(r'「\{\d+\}」' if lang == 'ja' else r'“\{\d+\}”', t) is not None)
    if re.match(r'^(Error|Warning):', en):
        want = {'ja': ('エラー：', '警告：'), 'zh': ('错误：', '警告：')}[lang]
        res.append(t.startswith(want))
    if lang == 'ja':
        res.append(len(re.findall(CJK + r' [A-Za-z0-9]', t)) + len(re.findall(r'[A-Za-z0-9] ' + CJK, t)) == 0)
    else:
        res.append(len(re.findall(CJK + r'[A-Za-z0-9]', t)) + len(re.findall(r'[A-Za-z0-9]' + CJK, t)) == 0)
    return len(res), sum(res)


ids = [i for i in hold if i in claude]
missing = [i for i in hold if i not in claude]
stats = {k: {'exact': 0, 'sim': 0.0, 'ph_bad': 0, 'g_n': 0, 'g_ok': 0, 's_n': 0, 's_ok': 0} for k in ('claude', 'ls', 'final')}
changed = [i for i in ids if hold[i][1] != hold[i][2]]
for i in ids:
    en, ls, fin = hold[i]
    cl = claude[i][0]
    for k, t in (('claude', cl), ('ls', ls), ('final', fin)):
        s = stats[k]
        s['exact'] += t == fin
        s['sim'] += sim(t, fin)
        s['ph_bad'] += sorted(PH.findall(t)) != sorted(PH.findall(en))
        n, ok = gloss_hits(en, t)
        s['g_n'] += n
        s['g_ok'] += ok
        n, ok = style_checks(en, t)
        s['s_n'] += n
        s['s_ok'] += ok

lines = []
N = len(ids)
lines.append('# %s: %d holdout strings scored (%d missing from Claude output)' % (lang, N, len(missing)))
lines.append('')
lines.append('| measure | Claude draft | professional draft | reviewed final |')
lines.append('|---|---|---|---|')
f = lambda a, b: '%d/%d (%.1f%%)' % (a, b, 100.0 * a / b if b else 0)
lines.append('| exact match with final | %s | %s | - |' % (f(stats['claude']['exact'], N), f(stats['ls']['exact'], N)))
lines.append('| mean char similarity to final | %.3f | %.3f | 1.000 |' % (stats['claude']['sim'] / N, stats['ls']['sim'] / N))
lines.append('| placeholder set differs from English | %d | %d | %d |' % (stats['claude']['ph_bad'], stats['ls']['ph_bad'], stats['final']['ph_bad']))
lines.append('| glossary term rendered as glossary | %s | %s | %s |' % tuple(f(stats[k]['g_ok'], stats[k]['g_n']) for k in ('claude', 'ls', 'final')))
lines.append('| style-guide checks passed | %s | %s | %s |' % tuple(f(stats[k]['s_ok'], stats[k]['s_n']) for k in ('claude', 'ls', 'final')))
lines.append('')
# the strings reviewers changed: the professional draft needed an edit there
ce = sum(claude[i][0] == hold[i][2] for i in changed)
closer = sum(sim(claude[i][0], hold[i][2]) > sim(hold[i][1], hold[i][2]) for i in changed)
lines.append('Strings the reviewers changed from the professional draft: %d. Claude matched the reviewed final exactly on %d; '
             'was closer to the final than the professional draft on %d.' % (len(changed), ce, closer))
unchanged = [i for i in ids if hold[i][1] == hold[i][2]]
lines.append('Strings the reviewers accepted unchanged: %d. Claude matched them exactly on %d (%.1f%%).'
             % (len(unchanged), sum(claude[i][0] == hold[i][2] for i in unchanged),
                100.0 * sum(claude[i][0] == hold[i][2] for i in unchanged) / max(1, len(unchanged))))
lines.append('')
lines.append('Claude confidence vs outcome (exact match with final / mean similarity):')
for conf in ('high', 'medium', 'low'):
    sel = [i for i in ids if claude[i][1] == conf]
    if sel:
        lines.append('- %s: %d strings, exact %s, similarity %.3f' % (
            conf, len(sel), f(sum(claude[i][0] == hold[i][2] for i in sel), len(sel)),
            sum(sim(claude[i][0], hold[i][2]) for i in sel) / len(sel)))
lines.append('')
lines.append('Largest Claude-vs-final differences (for manual reading):')
worst = sorted(ids, key=lambda i: sim(claude[i][0], hold[i][2]))[:25]
for i in worst:
    en, ls, fin = hold[i]
    lines.append('- %s EN: %s' % (i, en.replace('\n', ' ')[:140]))
    lines.append('  - Claude: %s  [%s] %s' % (claude[i][0].replace('\n', ' ')[:140], claude[i][1], claude[i][2][:100]))
    lines.append('  - Pro:    %s' % ls.replace('\n', ' ')[:140])
    lines.append('  - Final:  %s' % fin.replace('\n', ' ')[:140])
text = '\n'.join(lines)
print(text)
if out_path:
    open(out_path, 'w', encoding='utf-8').write(text)
