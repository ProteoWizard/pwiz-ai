"""Most frequent 1-4 word n-grams in Osprey's English resources (placeholders and stopword-edged
n-grams dropped), to pick glossary candidates from.

ngrams.py <osprey-inventory.tsv> <min count>
"""
import collections
import re
import sys

STOP = set('a an the of to in on for and or with by from at as is are be was were it its this that these those '
           'no not can cannot will would should must has have had than then so but if when which into per each '
           'one all any more only after before same other their them they there here use using used run'.split())

counts = collections.Counter()
for i, line in enumerate(open(sys.argv[1], encoding='utf-8')):
    if i == 0:
        continue
    en = line.split('\t')[2]
    en = re.sub(r'\{[^}]*\}', ' ', en.replace('\\n', ' '))
    words = re.findall(r"[A-Za-z][A-Za-z0-9'/-]*", en)
    seen = set()
    for n in (1, 2, 3, 4):
        for j in range(len(words) - n + 1):
            g = words[j:j + n]
            if g[0].lower() in STOP or g[-1].lower() in STOP:
                continue
            key = ' '.join(w.lower() for w in g)
            if key not in seen:  # count resources, not occurrences
                seen.add(key)
                counts[key] += 1
mn = int(sys.argv[2])
for k, v in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
    if v >= mn:
        print(v, k)
