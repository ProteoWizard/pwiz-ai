"""Wrap zh placeholders that carry command-line text (a --flag or --task <Name>) in “ ”, following
Skyline's zh CLI help (需要“--reintegrate-model-name”). Brendan, 2026-09-29: "follow the Skyline style".

apply_zh_quotes.py   (reads flag-args.tsv from flag_args.py; edits osprey-xlate/osprey.{zh,both}.tsv)
Also applies the reworded ParquetScoreCache_RequireCharge message in both languages.
"""
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
# Call-site scan hits that are not command-line text in a sentence: group titles list their member
# arguments; ProcessFile_Loaded's {3} is a whole appended sentence (its own {1} is quoted there).
EXCLUDE = re.compile(r'^OspreyCommandArgs_Group_|^PerFileScoringTask_ProcessFile_Loaded_')
flag_idx = {}
for i, line in enumerate(open('flag-args.tsv', encoding='utf-8')):
    if i == 0:
        continue
    key, idx, _ = line.rstrip('\n').split('\t')
    if not EXCLUDE.search(key):
        flag_idx[key] = [int(x) for x in idx.split(',')]
# --help usage text: flags supplied through DescriptionArgs (ARG_*.ArgumentText), by argument name.
for name, idx in {'input-list': [0], 'output-dir': [0], 'cache-dir': [1], 'reconciliation-compaction-fdr': [0],
                  'fdrbench': [0], 'fdrbench-per-run': [0], 'fdrbench-pass': [0], 'decoy-pairing-manifest': [0],
                  'task': [3], 'parallel-files': [0], 'threads': [0], 'memstamp': [0]}.items():
    flag_idx['_' + name.replace('-', '_')] = idx

REWORD_KEY = 'ParquetScoreCache_RequireCharge__0__is_corrupt__row__1___entry_id__2___has_a_charge_of_0__which_is_not_a_possible_'
REWORD = ('{0} is damaged: row {1} ({3} {2}) has a charge of 0, which is not a possible precursor charge. '
          'Delete the file and run {4} again to rewrite it.',
          '{0}は破損しています：行{1}（{3} {2}）の電荷が0ですが、これはプリカーサーの電荷としてあり得ません。'
          'ファイルを削除し、{4}を再実行して書き直してください。',
          '{0} 已损坏：第 {1} 行（{3} {2}）的电荷为 0，这不是可能的母离子电荷。请删除该文件并重新运行{4}以重写该文件。')


def quote(zh, indices):
    for i in indices:
        ph = '{%d}' % i
        if ph not in zh or ('“' + ph + '”') in zh:
            continue
        # full-width quotes are CJK punctuation: no space between them and neighboring text
        zh = re.sub(r' ?' + re.escape(ph) + r' ?', '“' + ph + '”', zh)
    return zh


def edit(path, zh_col, ja_col=None):
    lines = open(path, encoding='utf-8').read().split('\n')
    changed = 0
    for n, line in enumerate(lines):
        c = line.split('\t')
        if len(c) < 4 or n == 0:
            continue
        key = c[1]
        before = list(c)
        if key == REWORD_KEY:
            c[2] = REWORD[0]
            if ja_col is not None:
                c[ja_col] = REWORD[1]
            if zh_col is not None:
                c[zh_col] = REWORD[2]
        if zh_col is not None and key in flag_idx:
            c[zh_col] = quote(c[zh_col], flag_idx[key])
        if c != before:
            changed += 1
            lines[n] = '\t'.join(c)
    open(path, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
    print(path, changed, 'rows changed')


edit('osprey-xlate/osprey.zh.tsv', 3)
edit('osprey-xlate/osprey.ja.tsv', None, 3)
edit('osprey-xlate/osprey.both.tsv', 4, 3)
