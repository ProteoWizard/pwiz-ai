"""Crude text recovery from a Word 97 .doc: emit runs of UTF-16LE text (ASCII, CJK, kana, full-width
punctuation) of 4+ chars. Good enough to read a style guide; not a faithful conversion.

doc_strings.py <in.doc> <out.txt>
"""
import re
import sys

data = open(sys.argv[1], 'rb').read()
text = data.decode('utf-16le', errors='replace')
ok = re.compile(r'[\u0009\u000a\u000d -~ -ÿ‐-›　-ヿ一-鿿＀-￯]{4,}')
runs = [m.group(0) for m in ok.finditer(text)]
# the odd-byte alignment catches text stored at odd offsets
text2 = data[1:].decode('utf-16le', errors='replace')
runs2 = [m.group(0) for m in ok.finditer(text2)]
best = runs if sum(map(len, runs)) >= sum(map(len, runs2)) else runs2
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('\n'.join(r.replace('\r', '\n') for r in best))
print(len(best), 'runs', sum(map(len, best)), 'chars')
