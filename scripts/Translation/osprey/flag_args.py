"""For each Osprey resource, find which {N} placeholders are filled with command-line text (a --flag,
or --task <Name>), by parsing the arguments at every call site that formats the resource.

flag_args.py <osprey dir> <out.tsv>
Output: key, indices (comma list), evidence (the argument expressions).
"""
import collections
import glob
import os
import re
import sys

root, out = sys.argv[1], sys.argv[2]
FLAG_EXPR = re.compile(r'OspreyArgNames\.|\bARG_[A-Z_]+|TaskText\(|ArgumentText|ArgText\(')
key_re = re.compile(r'Osprey\w*Resources\.(\w+)|OspreyCommandArgUsage\.(\w+)')


def split_args(src, start):
    """Arguments after position `start` (just past the resource reference) up to the closing paren
    of the enclosing call; returns the list of top-level argument expressions."""
    depth, cur, args, i = 0, [], [], start
    in_str = None
    while i < len(src):
        c = src[i]
        if in_str:
            cur.append(c)
            if c == in_str and src[i - 1] != '\\':
                in_str = None
            i += 1
            continue
        if c in '"\'':
            in_str = c
            cur.append(c)
        elif c in '([{':
            depth += 1
            cur.append(c)
        elif c in ')]}':
            if depth == 0:
                args.append(''.join(cur).strip())
                return args
            depth -= 1
            cur.append(c)
        elif c == ',' and depth == 0:
            args.append(''.join(cur).strip())
            cur = []
        elif c == ';' and depth == 0:
            return args
        else:
            cur.append(c)
        i += 1
    return args


hits = collections.defaultdict(lambda: collections.defaultdict(set))
for path in glob.glob(os.path.join(root, '**', '*.cs'), recursive=True):
    if os.sep + 'obj' + os.sep in path or os.sep + 'bin' + os.sep in path or path.endswith('Designer.cs') \
            or os.sep + 'Osprey.Test' + os.sep in path:
        continue
    src = open(path, encoding='utf-8-sig').read()
    for m in key_re.finditer(src):
        key = m.group(1) or m.group(2)
        rest = src[m.end():]
        if not rest.lstrip().startswith(','):
            continue
        args = split_args(src, m.end() + rest.index(',') + 1)
        for i, a in enumerate(args):
            if FLAG_EXPR.search(a):
                hits[key][i].add(re.sub(r'\s+', ' ', a)[:80])
with open(out, 'w', encoding='utf-8', newline='') as f:
    f.write('key\tindices\tevidence\n')
    for key in sorted(hits):
        idx = sorted(hits[key])
        f.write('%s\t%s\t%s\n' % (key, ','.join(map(str, idx)), ' | '.join('{%d}=%s' % (i, ' / '.join(sorted(hits[key][i]))) for i in idx)))
print(len(hits), 'resources format command-line text into a placeholder')
