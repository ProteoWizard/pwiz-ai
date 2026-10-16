"""Blind A/B grading sample for the expert reviewers: holdout strings where Claude's blind draft and
the professional draft differ, the two shown in random order with no labels.

blind_sample.py <session dir> <n per language>
Writes eval/blind-grading.<lang>.csv (for the reviewer) and eval/blind-grading-key.<lang>.csv (kept
back). Half the sample is drawn from strings the reviewers changed, half from strings they accepted,
so the grading covers both kinds.
"""
import csv
import os
import random
import sys

sd, n = sys.argv[1], int(sys.argv[2])
rng = random.Random(20260928)


def unesc(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')


for lang in ('ja', 'zh'):
    hold = [l.rstrip('\n').split('\t') for l in open(os.path.join(sd, 'eval', 'holdout.%s.tsv' % lang), encoding='utf-8')][1:]
    cl = {r[0]: r for r in (l.rstrip('\n').split('\t') for l in open(os.path.join(sd, 'eval-blind', 'claude.%s.tsv' % lang), encoding='utf-8'))}
    diff = [h for h in hold if cl[h[0]][1] != h[3]]
    changed = [h for h in diff if h[3] != h[4]]
    accepted = [h for h in diff if h[3] == h[4]]
    k = min(len(changed), n // 2)
    pick = rng.sample(changed, k) + rng.sample(accepted, n - k)
    rng.shuffle(pick)
    lab = 'ja' if lang == 'ja' else 'zh-Hans'
    with open(os.path.join(sd, 'eval', 'blind-grading.%s.csv' % lab), 'w', encoding='utf-8-sig', newline='') as f, \
            open(os.path.join(sd, 'eval', 'blind-grading-key.%s.csv' % lab), 'w', encoding='utf-8-sig', newline='') as fk:
        w = csv.writer(f)
        wk = csv.writer(fk)
        w.writerow(['Item', 'English', 'A', 'B', 'Grade A (accept / minor edit / wrong)', 'Grade B (accept / minor edit / wrong)', 'Preferred (A / B / same)', 'Comment'])
        wk.writerow(['Item', 'A is', 'B is', 'Reviewers changed the professional draft'])
        for i, h in enumerate(pick, 1):
            claude, pro = unesc(cl[h[0]][1]), unesc(h[3])
            a_is_claude = rng.random() < 0.5
            a, b = (claude, pro) if a_is_claude else (pro, claude)
            w.writerow([i, unesc(h[2]), a, b, '', '', '', ''])
            wk.writerow([i, 'Claude' if a_is_claude else 'professional', 'professional' if a_is_claude else 'Claude',
                         'yes' if h[3] != h[4] else 'no'])
    print(lab, 'sample', len(pick), '(%d reviewer-changed)' % k)
